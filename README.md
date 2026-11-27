# Projeto de Engenharia de Dados — Grupo 03

Data Lake de passagens aéreas na AWS, provisionado 100% em Terraform, para a
disciplina de Engenharia de Dados (CESAR School, 2026.2).

> **Pergunta de negócio:** o valor das passagens é influenciado pelo horário de
> embarque e desembarque?

**Fonte do dataset:** [Airlines Flights Data](https://www.kaggle.com/datasets/rohitgrewal/airlines-flights-data),
publicado no Kaggle por *Data Science Lovers* (`rohitgrewal`), versão 1
(29/07/2025). Licença: **Open Database License (ODbL)** para a base e
**Database Contents License (DbCL)** para o conteúdo. Ofertas de passagens
aéreas entre cidades da Índia, coletadas pelo autor por raspagem de um site
de reservas. O autor não diz qual site.
- Uma cópia está versionada em [`dados/airlines_flights_data.csv.gz`](dados/),
  sob a mesma licença, com esta atribuição.
- O CSV descompactado tem **24.946.485 bytes**, exatamente o tamanho informado
  pela API do Kaggle. Ou seja, o arquivo não foi alterado.
- 300.153 linhas.

| Parte | Pasta | O que entrega |
|---|---|---|
| Parte 1 (AV1) | [`parte-1/`](parte-1/) — guia em [`parte-1/README.md`](parte-1/README.md) | bucket, Glue Data Catalog e Athena; consulta respondida com custo medido |
| **Parte 2 (AV2)** | [`parte-2/`](parte-2/) — **este guia** | camadas raw/trusted/refined, Parquet particionado, ingestão idempotente com backfill, Lake Formation e meta de custo |

As decisões de engenharia (grão, chaves, partição, formato, custo), com os
números medidos, estão em [`DECISOES.md`](DECISOES.md).

---

## Status do projeto

Atualizado em 27/11/2026. Entrega da Parte 2: **30/11/2026 (Aula 30)**.

### Já feito

**Parte 1 (AV1) — entregue**
- [x] Bucket, Glue Data Catalog e workgroup do Athena em Terraform, com módulo, backend remoto (S3 + DynamoDB) e workspace `dev`
- [x] Schema declarado no IaC (sem Crawler) e tabela trusted com grão definido
- [x] Pergunta de negócio respondida no Athena com custo medido (24,95 MB escaneados)
- [x] `verifica.sh`, `DECISOES.md`, README com evidências e destroy

**Parte 2 (AV2) — implementada e verificada na conta do grupo**
- [x] Três camadas raw / trusted / refined, uma database do Glue por camada
- [x] trusted e refined em Parquet (Snappy) particionado: `source_city` e `class`
- [x] Meta de custo declarada (≤ 1 MiB por consulta de negócio) e cumprida: 1.435 B escaneados
- [x] Ingestão idempotente em Athena SQL, com backfill de partição (`ingestao.sh --particao`)
- [x] Permissão por camada via Lake Formation (personas analista e cientista), testada com consultas reais
- [x] `DECISOES.md` fechado: grão, chaves, partição, formato e custo, cada um com número medido
- [x] `verifica.sh` da Parte 2: **100/100** em 27/11/2026 ([`verifica.log`](evidencias/parte-2/logs/verifica.log))
- [x] Ciclo completo do zero em 27/11: destroy → apply (44 recursos) → ingestão ×2 → backfill → `verifica.sh` 100/100 → destroy final (44 recursos, pós-destroy 100/100)
- [x] Bug do destroy encontrado (3 databases órfãs), corrigido e provado — `DECISOES.md`, seção 9
- [x] Evidências em texto no lugar de prints: logs + medições com QueryExecutionId (`evidencias/parte-2/`)
- [x] Fonte do dataset citada (Kaggle, versão 1, licença ODbL/DbCL)
- [x] Scripts compatíveis com macOS, Linux e Windows (Git Bash)
- [x] Bootstrap do backend em Terraform, testado: apply e destroy de 5 recursos (`bootstrap-apply.log`, `bootstrap-destroy.log`)
- [x] Regras de limpeza testadas com lote sujo: 12 de 14 linhas barradas (`verifica-rodada2.log`, critério 5b)
- [x] Dataset versionado em `dados/` (CSV gzip) para subir em conta limpa

### Falta fazer

- [ ] Apresentação `apresentacao-parte-2-g03.pdf` (5 min, diretriz de design da CESAR School)
- [ ] Ensaiar a defesa individual: cada integrante precisa saber explicar qualquer decisão do `DECISOES.md`
- [ ] Merge na `main`, tags `av1-entrega` (commit `b54260b`) e `av2-entrega`
- [ ] Submissão no Google Classroom pelo representante (link do repositório + PDF)
- [ ] Opcional (bônus): ingestão near real-time com Kinesis Data Firehose

---

## 1. Arquitetura da Parte 2

```text
dados/airlines_flights_data.csv.gz
        │  parte-2/scripts/ingestao.sh  (Athena SQL, idempotente)
        ▼
┌─────────────────────────┐   limpeza, tipagem,   ┌──────────────────────────┐   agregação   ┌──────────────────────────────┐
│ RAW                     │   deduplicação        │ TRUSTED                  │               │ REFINED                      │
│ eda262-g03-lake-raw     │ ────────────────────▶ │ eda262-g03-lake-trusted  │ ────────────▶ │ eda262-g03-lake-refined      │
│ CSV gzip (como recebido)│                       │ Parquet, por source_city │               │ Parquet, por class           │
│ eda262_g03_raw.flights  │                       │ eda262_g03_trusted.flights│              │ eda262_g03_refined.          │
│                         │                       │ grão: 1 oferta           │               │   preco_por_periodo          │
└─────────────────────────┘                       └──────────────────────────┘               └──────────────────────────────┘
        ▲ só engenheiro                                   ▲ engenheiro, cientista                    ▲ engenheiro, cientista, analista
        └──────────────────── permissões por camada: AWS Lake Formation ──────────────────────────────┘

Consultas: Athena workgroup eda262-g03-athena  →  resultados em eda262-g03-athena-results
State:     S3 eda262-g03-terraform-state + lock DynamoDB eda262-g03-terraform-locks (workspace dev)
```

Serviços: Amazon S3, AWS Glue Data Catalog, Amazon Athena, AWS Lake Formation,
IAM, DynamoDB (lock do state). Região: **us-east-1**.

Todos os recursos seguem o prefixo `eda262-g03-` (databases do Glue:
`eda262_g03_`, porque o Glue não aceita hífen) e levam as tags
`turma=eda262`, `grupo=g03`, `projeto=engenharia-de-dados`, aplicadas via
`default_tags` do provider.

---

## 2. Estrutura do repositório

```text
eda262-projeto-g03/
├── DECISOES.md                       decisões de engenharia com números medidos
├── README.md                         este guia (Parte 2)
├── dados/
│   └── airlines_flights_data.csv.gz  dataset (300.153 linhas)
├── parte-1/                          entrega da AV1 (histórico)
├── parte-2/
│   ├── backend.tf  providers.tf  variables.tf  main.tf  outputs.tf
│   ├── bootstrap/            backend remoto (bucket de state + lock DynamoDB), state local
│   ├── modules/data-lake/
│   │   ├── s3.tf             buckets das camadas + resultados do Athena
│   │   ├── glue.tf           3 databases e 3 tabelas (schema declarado, sem Crawler)
│   │   ├── athena.tf         workgroup + consultas salvas
│   │   ├── iam.tf            role do Lake Formation e personas analista/cientista
│   │   ├── lakeformation.tf  configurações, registro dos buckets e grants por camada
│   │   └── locals.tf  variables.tf  outputs.tf
│   ├── sql/                  transformações e consultas de negócio
│   └── scripts/
│       ├── ingestao.sh            carga completa e backfill (idempotentes)
│       ├── athena.sh              funções compartilhadas
│       ├── coletar-evidencias.sh  roda as medições do DECISOES.md e grava a prova
│       ├── registrar.sh           grava a saída de um comando em evidencias/parte-2/logs/
│       └── migrar-da-parte-1.sh   histórico: migração de state Parte 1 → 2 (não é usado em conta limpa)
└── verificacao/
    ├── verifica.sh            aceite da Parte 2 (PASSA/FALHA por critério)
    └── verifica-parte-1.sh    aceite da Parte 1
```

---

## 3. Pré-requisitos

- Terraform ≥ 1.5 (testado com 1.9.8 e 1.16.0)
- AWS CLI configurada (`aws configure`), com permissão de administrador na conta
- **Bash** para os scripts: nativo no macOS e no Linux; no Windows, use o
  **Git Bash** (vem com o Git for Windows)
- Quem roda o Terraform vira **administrador do Lake Formation** da conta (é
  necessário para conceder as permissões por camada)

```bash
terraform --version
aws sts get-caller-identity
```

---

## 4. Backend remoto (uma vez por conta)

O state fica no S3 com lock no DynamoDB. Em uma conta limpa, o backend é
criado **também em Terraform**, pela pasta [`parte-2/bootstrap/`](parte-2/bootstrap/),
antes do primeiro `terraform init` da stack. Na raiz do repositório:

```bash
terraform -chdir=parte-2/bootstrap init
terraform -chdir=parte-2/bootstrap apply
```

O bootstrap cria o bucket `eda262-g03-terraform-state` (versionado,
criptografado, sem acesso público) e a tabela `eda262-g03-terraform-locks`,
ambos com as tags `turma`, `grupo` e `projeto`. Ele usa **state local**
(`parte-2/bootstrap/terraform.tfstate`, fora do Git), porque o backend
remoto ainda não existe quando ele roda.

Nomes de bucket são globais: se `eda262-g03-terraform-state` já existir em
outra conta, escolha outro nome nos dois passos:

```bash
terraform -chdir=parte-2/bootstrap apply -var="bucket_state=<seu-bucket>"
terraform -chdir=parte-2 init -backend-config="bucket=<seu-bucket>"
```

O output `proximo_passo` do bootstrap já mostra o comando de init certo.

Testado em 27/11 com nomes de teste (`-var="tabela_lock=..."` também é
aceito): 5 recursos criados e destruídos —
[`bootstrap-apply.log`](evidencias/parte-2/logs/bootstrap-apply.log) e
[`bootstrap-destroy.log`](evidencias/parte-2/logs/bootstrap-destroy.log).

> Os buckets das camadas (`eda262-g03-lake-*`) também têm nome global. A
> infraestrutura do grupo precisa estar destruída antes de subir em outra conta.

---

## 5. Deploy

```bash
cd parte-2
terraform init
terraform workspace select dev || terraform workspace new dev
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
```

Em conta limpa, o apply cria 44 recursos ([`evidencias/parte-2/logs/apply.log`](evidencias/parte-2/logs/apply.log)). Saída esperada (`terraform output`):

```text
athena_results_bucket_name = "eda262-g03-athena-results"
athena_workgroup_name      = "eda262-g03-athena"
buckets        = { raw = "eda262-g03-lake-raw", refined = "eda262-g03-lake-refined", trusted = "eda262-g03-lake-trusted" }
glue_databases = { raw = "eda262_g03_raw", refined = "eda262_g03_refined", trusted = "eda262_g03_trusted" }
glue_tables    = { raw = "eda262_g03_raw.flights", refined = "eda262_g03_refined.preco_por_periodo", trusted = "eda262_g03_trusted.flights" }
```

---

## 6. Ingestão

Na raiz do repositório:

```bash
# carga completa: raw -> trusted (6 partições) -> refined
bash parte-2/scripts/ingestao.sh

# backfill de uma partição (reprocessa só source_city=Delhi a partir da raw)
bash parte-2/scripts/ingestao.sh --particao Delhi
```

As duas formas podem ser executadas quantas vezes quiser: cada partição é
sobrescrita (DROP PARTITION → remoção do prefixo no S3 → INSERT), então não há
duplicação. Resultado da carga completa:

```text
raw:     300153 linhas
trusted: 300153 linhas, 300153 id_oferta distintos  (descartadas na limpeza: 0)
refined: soma de qtd_passagens = 300153
ingestão concluída — total escaneado nesta execução: 16.79 MB
```

A carga completa leva cerca de 3 minutos (≈ 10 consultas sequenciais no Athena).

---

## 7. Consultas da pergunta de negócio

As consultas estão em [`parte-2/sql/`](parte-2/sql/) e também ficam salvas no
Athena (named queries `eda262-g03-negocio-refined` e `eda262-g03-negocio-trusted`).

```sql
SELECT departure_time, arrival_time,
       SUM(qtd_passagens) AS quantidade_passagens,
       ROUND(CAST(SUM(soma_preco) AS DOUBLE) / SUM(qtd_passagens), 2) AS preco_medio
FROM eda262_g03_refined.preco_por_periodo
GROUP BY departure_time, arrival_time
ORDER BY preco_medio DESC;
```

| Camada consultada | Bytes escaneados | Resultado (topo) |
|---|---|---|
| refined | **1.435 B** | Night → Evening, 9.209 ofertas, 31.425,82 |
| trusted (Parquet) | 605.338 B | idem |
| Parte 1 (CSV, remedido) | 24.946.485 B | idem |

Medido em 27/11/2026: [`evidencias/parte-2/medicoes/resumo.csv`](evidencias/parte-2/medicoes/resumo.csv)
(resultados em `10_negocio_refined.csv`, `11_negocio_trusted.csv` e `90_parte1_csv.csv`).

**Meta de custo declarada: ≤ 1 MiB por consulta de negócio — cumprida (1.435 B).**
Análise completa e custo monetário em [`DECISOES.md`](DECISOES.md), seções 7 e 11.

---

## 8. Verificação

Rode **depois** do deploy (seção 5) **e** da carga completa (seção 6). Sem
dados nas camadas, os critérios 5 a 7 falham.

```bash
bash verificacao/verifica.sh
```

| Critério | O que confere | Peso |
|---|---|---|
| 0 | módulo, backend S3 + DynamoDB, workspace | pré-requisito |
| 1 | `terraform plan` sem mudanças | 10 |
| 2 | 4 buckets existem e têm as 3 tags | 10 |
| 3 | 3 databases/tabelas; trusted e refined em Parquet particionado; sem Crawler | 15 |
| 4 | buckets registrados no Lake Formation + matriz de acesso testada com consultas reais de cada persona | 15 |
| 5a | trusted sem duplicatas e refined fechando com a trusted | 5 |
| 5b | regras de limpeza testadas com um lote sujo de 14 linhas ([`limpeza_sujeira_valores.sql`](parte-2/sql/testes/limpeza_sujeira_valores.sql)): só as 2 válidas passam | 5 |
| 6 | backfill real de `source_city=Delhi` sem alterar a contagem | 15 |
| 7 | consulta de negócio ≤ meta de custo e refined = trusted | 15 |
| 8 | `DECISOES.md` com grão, chave, partição, formato, custo, idempotência e acesso | 10 |

Use `--sem-backfill` para pular o critério 6 (mais rápido).

### Evidência

As evidências ficam **versionadas em texto** em [`evidencias/parte-2/`](evidencias/parte-2/):

| Arquivo | O que prova |
|---|---|
| `logs/*.log` | saída de apply, ingestão, backfill, `verifica.sh`, destroy e pós-destroy, com data, conta, commit e código de saída |
| `medicoes/resumo.csv` | uma linha por medição do `DECISOES.md`: QueryExecutionId, bytes escaneados, tempo, custo cobrado e o `.sql` usado |
| `medicoes/<medicao>.csv` | resultado de cada consulta, baixado do próprio Athena |
| `medicoes/tamanhos-s3.txt` | tamanho em disco de cada camada |

Roteiro de coleta, na raiz do repositório. O `registrar.sh` roda o comando e
grava a saída em `evidencias/parte-2/logs/<nome>.log`:

```bash
bash parte-2/scripts/registrar.sh apply            terraform -chdir=parte-2 apply -no-color
bash parte-2/scripts/registrar.sh ingestao         bash parte-2/scripts/ingestao.sh
bash parte-2/scripts/registrar.sh ingestao-de-novo bash parte-2/scripts/ingestao.sh   # idempotência
bash parte-2/scripts/registrar.sh backfill         bash parte-2/scripts/ingestao.sh --particao Delhi
bash parte-2/scripts/registrar.sh coleta           bash parte-2/scripts/coletar-evidencias.sh --parte1-csv
bash parte-2/scripts/registrar.sh verifica         bash verificacao/verifica.sh
bash parte-2/scripts/registrar.sh destroy          terraform -chdir=parte-2 destroy -no-color
bash parte-2/scripts/registrar.sh pos-destroy      bash verificacao/verifica.sh --pos-destroy
```

O SQL de cada medição está em [`parte-2/sql/medicoes/`](parte-2/sql/medicoes/),
com a afirmação do `DECISOES.md` que ele comprova no cabeçalho.

---

## 9. Destroy

```bash
cd parte-2
terraform destroy
cd ..
bash verificacao/verifica.sh --pos-destroy
```

Os buckets têm `force_destroy = true` (os dados gravados pela ingestão não
impedem o destroy), o workgroup tem `force_destroy = true` (remove o histórico),
a role do Lake Formation é gerenciada pelo Terraform (não se usa a
service-linked role, que ficaria órfã) e as partições do Glue são apagadas
junto com as tabelas. O `--pos-destroy` confere que não sobrou bucket,
database, workgroup, role ou registro no Lake Formation do grupo.

Para não deixar nem o backend na conta, destrua o bootstrap **por último**
(antes disso o state da stack ainda está lá):

```bash
terraform -chdir=parte-2/bootstrap destroy
```

O bucket de state tem `force_destroy = true`: as versões antigas do state
não impedem o destroy.

### Evidência

[`evidencias/parte-2/logs/destroy.log`](evidencias/parte-2/logs/destroy.log) e
[`evidencias/parte-2/logs/pos-destroy.log`](evidencias/parte-2/logs/pos-destroy.log)
(roteiro na seção 8).

---

## 10. Continuidade com a Parte 1 (conta do grupo)

**Em uma conta limpa esta seção não se aplica**: siga as seções 4 a 6.

Histórico: em 26/11, a Parte 2 foi construída sobre a infraestrutura da Parte 1.
O bucket `eda262-g03-lake-trusted` e o workgroup `eda262-g03-athena` passaram
para o state da Parte 2 via `terraform import`
(`parte-2/scripts/migrar-da-parte-1.sh`), e a database `eda262_g03_flights`
foi substituída por `eda262_g03_trusted`, porque tinha o grant padrão
`IAM_ALLOWED_PRINCIPALS`, incompatível com o controle por camada.

Em 27/11, para provar que a Parte 2 sobe do zero, **tudo foi destruído e
recriado só pelo Terraform**, sem nenhum `import`. Os logs estão em
[`evidencias/parte-2/logs/`](evidencias/parte-2/logs/) (`destroy-inicial*`,
`apply`, `verifica`, `destroy`). O script de migração fica só como registro.
