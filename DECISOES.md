# DECISOES.md — Grupo 03

Decisões de engenharia do Data Lake de passagens aéreas, **Partes 1 e 2**.
Cada decisão traz o número medido que a sustenta **e o arquivo versionado que
o prova**. Medições de 27/11/2026 na conta 325583868777 (us-east-1), workgroup
`eda262-g03-athena`, com o código do commit `211e3af`, numa infraestrutura
recém-criada do zero (destroy → apply → ingestão).

**Onde estão as provas**
- [`evidencias/parte-2/medicoes/resumo.csv`](evidencias/parte-2/medicoes/resumo.csv):
  uma linha por medição, com o QueryExecutionId do Athena, os bytes escaneados,
  o tempo e o custo cobrado.
- `evidencias/parte-2/medicoes/NN_*.csv`: o resultado de cada consulta, baixado
  do Athena. O SQL que gerou cada um está em [`parte-2/sql/medicoes/`](parte-2/sql/medicoes/)
  e [`parte-2/sql/`](parte-2/sql/).
- [`evidencias/parte-2/logs/`](evidencias/parte-2/logs/): saída de apply,
  ingestão, backfill, `verifica.sh` e destroy, em texto.

Para reproduzir: `bash parte-2/scripts/coletar-evidencias.sh --parte1-csv`.

## Resumo das decisões

| Decisão | Escolha | Número que comprova | Prova |
|---|---|---|---|
| Grão (trusted) | 1 linha = 1 oferta de passagem (observação de preço) | 300.153 linhas = 300.153 `id_oferta` distintos; 1.555 combinações voo/rota/classe/dia/período aparecem com preços diferentes | `01`, `05` |
| Grão (refined) | `class` × `departure_time` × `arrival_time` | 71 linhas (36 Economy + 35 Business) resumem 300.153 ofertas | `01`, `07` |
| Chave | `id_oferta` (surrogate vindo do `index` da fonte) | 0 duplicatas; chave natural candidata colide em 1.555 grupos | `01`, `04`, `05` |
| Partição | trusted por `source_city`; refined por `class` | filtro por cidade: 377,54 KB → 78,69 KB (−79,2%); filtro por classe: 1.435 B → 913 B | `08`, `09`, `10`, `12` |
| Formato | raw CSV gzip; trusted e refined Parquet Snappy | mesma consulta: CSV 24,95 MB → Parquet 605,34 KB (−97,6%) → refined 1,44 KB | `90`, `11`, `10` |
| Custo | meta ≤ 1 MiB escaneado na consulta de negócio | medido: **1.435 bytes** (0,14% da meta) | `10`, `logs/verifica.log` |
| Idempotência | sobrescrita por partição (DROP + rm + INSERT) | 2 cargas completas seguidas: 300.153 → 300.153; backfill de Delhi: 61.343 → 61.343 | `logs/ingestao*.log`, `logs/backfill.log` |
| Acesso | 1 database por camada + Lake Formation | analista negado na trusted/raw ("Insufficient Lake Formation permission(s)") e liberado na refined | `logs/verifica.log` |
| Destroy | sem recurso órfão | 1º destroy deixou 3 databases órfãs; causa corrigida; pós-destroy 100/100 | `logs/destroy-inicial*.log`, `logs/pos-destroy-inicial*.log` |

Os números da coluna "Prova" são os prefixos dos arquivos em
`evidencias/parte-2/medicoes/` (ex.: `05` = `05_chave_natural_colisoes.csv`).

---

## 1. Cenário e pergunta de negócio

Dataset de passagens aéreas (companhia, voo, origem, destino, período de
partida e chegada, escalas, classe, duração, antecedência e preço) —
**300.153 registros**, 24,95 MB em CSV.

**Pergunta:** o valor das passagens é influenciado pelo horário de embarque e
desembarque?

O dataset não traz horário exato, e sim períodos do dia (`Early_Morning`,
`Morning`, `Afternoon`, `Evening`, `Night`, `Late_Night`) em `departure_time`
e `arrival_time`.

---

## 2. Arquitetura em camadas (Parte 2)

| Camada | Bucket | Database / tabela | Formato | Conteúdo |
|---|---|---|---|---|
| raw | `eda262-g03-lake-raw` | `eda262_g03_raw.flights` | CSV gzip, todas as colunas `string` | arquivo como recebido |
| trusted | `eda262-g03-lake-trusted` | `eda262_g03_trusted.flights` | Parquet Snappy, partição `source_city` | ofertas limpas e tipadas |
| refined | `eda262-g03-lake-refined` | `eda262_g03_refined.preco_por_periodo` | Parquet Snappy, partição `class` | agregado da pergunta de negócio |

Resultados do Athena ficam num bucket separado (`eda262-g03-athena-results`).
Na Parte 1, os resultados gravados dentro do bucket de dados fizeram o
`COUNT(*)` subir de 300.153 para 300.178 e 300.181; separar os buckets
elimina esse risco por construção.

**Uma database por camada** (e não uma database com três tabelas) para que o
Lake Formation conceda acesso por camada com um grant por database.

---

## 3. Grão

### raw
1 linha = 1 linha do arquivo de origem, sem nenhuma transformação
(**300.153 linhas**). Todas as colunas são `string`: a raw não pode rejeitar
dados na leitura; tipagem é responsabilidade da trusted.

### trusted
**1 linha = 1 oferta de passagem**, ou seja, uma observação de preço de um voo
numa rota, classe, período e antecedência.

Por que não "1 linha = 1 voo por dia": medimos que **1.555 combinações** de
`airline, flight, source_city, destination_city, class, days_left,
departure_time, arrival_time, stops, duration` aparecem mais de uma vez com
**preços diferentes**. São observações distintas, não duplicatas — agregá-las
perderia informação de preço. Essas 1.555 combinações somam 3.142 ofertas.
Duplicatas exatas (todos os atributos iguais): **0**.

Prova: [`05_chave_natural_colisoes.csv`](evidencias/parte-2/medicoes/05_chave_natural_colisoes.csv)
e [`04_raw_duplicatas_exatas.csv`](evidencias/parte-2/medicoes/04_raw_duplicatas_exatas.csv).

### refined
**1 linha = `class` × `departure_time` × `arrival_time`**: exatamente o grão
da pergunta de negócio, com a classe junto porque é o principal fator de
confusão do preço (ver seção 9).

- **71 linhas** (36 Economy + 35 Business — uma combinação não ocorre em Business).
- Guarda `qtd_passagens` e `soma_preco` além de `preco_medio`: assim a média
  geral é recomposta exatamente (`SUM(soma_preco) / SUM(qtd_passagens)`) sem
  voltar à trusted. Verificado: o resultado na refined é idêntico ao da trusted
  e ao do CSV da Parte 1 (Night→Evening = 31.425,82 nas três). Os três arquivos
  [`10_negocio_refined.csv`](evidencias/parte-2/medicoes/10_negocio_refined.csv),
  [`11_negocio_trusted.csv`](evidencias/parte-2/medicoes/11_negocio_trusted.csv) e
  [`90_parte1_csv.csv`](evidencias/parte-2/medicoes/90_parte1_csv.csv) têm as
  mesmas 36 linhas.
- Prova das 71 linhas: [`07_refined_linhas_por_classe.csv`](evidencias/parte-2/medicoes/07_refined_linhas_por_classe.csv).

---

## 4. Chaves

| Camada | Chave | Evidência |
|---|---|---|
| trusted | `id_oferta` (BIGINT, vem do `index` do CSV) | 300.153 linhas, 300.153 distintos — [`01_contagem_camadas.csv`](evidencias/parte-2/medicoes/01_contagem_camadas.csv); o `verifica.sh` checa a cada execução |
| trusted | chave de deduplicação: os 11 atributos de negócio | 0 duplicatas na raw — [`04_raw_duplicatas_exatas.csv`](evidencias/parte-2/medicoes/04_raw_duplicatas_exatas.csv) |
| refined | (`class`, `departure_time`, `arrival_time`) | única por construção (`GROUP BY`) |

- Na Parte 1 o `index` foi mantido só para não deslocar colunas no CSV. Na
  Parte 2 ele vira **`id_oferta`**, uma surrogate key estável: é único e não
  muda entre cargas, então permite rastrear uma oferta da trusted até a linha
  da raw.
- A chave natural candidata foi descartada porque colide em 1.555 grupos (seção 3).

---

## 5. Partição

### trusted — `source_city`

| Partição | Registros |
|---|---|
| Bangalore | 52.061 |
| Chennai | 38.700 |
| Delhi | 61.343 |
| Hyderabad | 40.806 |
| Kolkata | 46.347 |
| Mumbai | 60.896 |

Prova: [`02_trusted_por_particao.csv`](evidencias/parte-2/medicoes/02_trusted_por_particao.csv).

- **Volume equilibrado**: a maior partição tem 1,6× a menor. 6 arquivos
  Parquet, 2.722.826 bytes (2,73 MB) no total (Delhi: 564.247 bytes) —
  [`tamanhos-s3.txt`](evidencias/parte-2/medicoes/tamanhos-s3.txt).
- **Unidade natural de carga e de backfill**: o dataset não tem data; a cidade
  de origem funciona como "lote" (o feed de cada aeroporto). Reprocessar uma
  cidade não toca nas outras cinco.
- **Pruning medido**: `AVG(price)` em todas as cidades escaneia 377.543 bytes;
  com `WHERE source_city = 'Delhi'`, 78.694 bytes (**−79,2%**) —
  medições `08_pruning_sem_filtro` e `09_pruning_delhi` no
  [`resumo.csv`](evidencias/parte-2/medicoes/resumo.csv).
- **Limitação assumida**: a consulta de negócio agrupa todas as cidades, então
  não se beneficia dessa partição. Quem atende a consulta de negócio é a
  refined (seção 7). A partição da trusted serve à carga, ao backfill e a
  análises por cidade.

Alternativas descartadas:
- `departure_time`: é a coluna agrupada pela pergunta, então a consulta lê
  todas as partições de qualquer jeito (zero pruning), e `Late_Night` teria só
  **1.306 linhas** (0,44% do total) — partição minúscula —
  [`06_distribuicao_departure_time.csv`](evidencias/parte-2/medicoes/06_distribuicao_departure_time.csv).
- data de ingestão: coluna sintética, sem significado de negócio e sem pruning
  útil para a pergunta.
- partições mais finas (cidade × companhia = até 36): arquivos ainda menores;
  com 2,73 MB no total, só aumentaria o overhead de arquivos pequenos.

### refined — `class`
A refined tem 71 linhas e 5.398 bytes; a partição existe para a análise por
classe: a consulta só de Economy escaneia **913 B** contra 1.435 B da consulta
geral (medições `12` e `10` no [`resumo.csv`](evidencias/parte-2/medicoes/resumo.csv)).

---

## 6. Formato

| Onde | Formato | Tamanho em disco | Bytes escaneados pela consulta de negócio | Prova |
|---|---|---|---|---|
| Parte 1 (trusted) | CSV | 24.946.485 B | **24.946.485 B** | `90_parte1_csv` |
| Parte 2 raw | CSV gzip | 1.871.576 B | 1.871.576 B (qualquer consulta) | `03`, `04` |
| Parte 2 trusted | Parquet Snappy | 2.722.826 B | **605.338 B** (−97,6% vs Parte 1) | `11_negocio_trusted` |
| Parte 2 refined | Parquet Snappy | 5.398 B | **1.435 B** (−99,99% vs Parte 1) | `10_negocio_refined` |

Bytes no [`resumo.csv`](evidencias/parte-2/medicoes/resumo.csv); tamanhos em
[`tamanhos-s3.txt`](evidencias/parte-2/medicoes/tamanhos-s3.txt). A linha da
Parte 1 foi **remedida** em 27/11: o `coletar-evidencias.sh --parte1-csv` sobe
o CSV sem compressão numa tabela temporária com o schema da Parte 1, roda a
mesma consulta e apaga tudo no fim. Deu exatamente o número registrado na AV1.

- **raw em CSV gzip**: guarda o arquivo como veio, 13× menor que o CSV puro.
  Gzip não é divisível nem colunar: qualquer consulta na raw lê o arquivo todo
  (1,87 MB). Por isso a raw não é camada de consulta.
- **trusted em Parquet**: em disco fica até maior que o gzip (2,73 MB vs
  1,87 MB), mas é colunar — a consulta de negócio lê só `departure_time`,
  `arrival_time` e `price`, e `COUNT(*)` é respondido pelos metadados do Parquet
  (**0 bytes** escaneados — medição `14_count_trusted_metadados`).
- **Snappy**: compressão rápida e padrão de mercado para Parquet; a diferença de
  tamanho para gzip é irrelevante neste volume.

---

## 7. Custo

### Meta de custo (declarada)

> **A consulta da pergunta de negócio escaneia no máximo 1 MiB (1.048.576 bytes).**

**Cumprida:** a consulta na refined escaneou **1.435 bytes**, 0,14% da meta.
- Na coleta: medição `10_negocio_refined` no [`resumo.csv`](evidencias/parte-2/medicoes/resumo.csv),
  com o QueryExecutionId.
- No `verifica.sh` ([`logs/verifica.log`](evidencias/parte-2/logs/verifica.log),
  critério 7): 1,43 KB, QueryExecutionId `75bd61e8-5d24-4c7c-9886-30a62edf6178`.

O valor oscila alguns bytes entre cargas (1.429 B em 26/11, 1.435 B em 27/11),
porque os arquivos Parquet da refined são regravados. A folga para a meta é de
mais de 700×. O critério 7 do `verifica.sh` roda a consulta e reprova se ela
passar da meta ou se o resultado divergir da trusted.

Proteção extra: o workgroup tem `bytes_scanned_cutoff_per_query = 100 MB`;
nenhuma consulta do grupo passa disso.

### Custo monetário

Athena cobra **US$ 5,00 por TB** escaneado, arredondado para cima ao MB, com
**mínimo de 10 MB por consulta**.

| Consulta | Bytes escaneados | Bytes cobrados | Custo por consulta |
|---|---|---|---|
| Parte 1 — CSV | 24.946.485 | 25 MB | US$ 0,000125 |
| Parte 2 — trusted Parquet | 605.338 | 10 MB (mínimo) | US$ 0,000050 |
| Parte 2 — refined | 1.435 | 10 MB (mínimo) | US$ 0,000050 |

Coluna `custo_cobrado_usd` do [`resumo.csv`](evidencias/parte-2/medicoes/resumo.csv).

Leitura honesta dos números: o volume escaneado caiu 99,99%, mas o custo cobrado
caiu 60%, porque as duas consultas da Parte 2 ficam abaixo do mínimo de 10 MB.
O ganho cresce com o volume: a refined tem no máximo 72 linhas (2 classes × 6 × 6
períodos) independentemente de quantas ofertas existam, enquanto o CSV da Parte 1
cresce linearmente com os dados.

### Custo da ingestão (medido)

| Execução | Bytes escaneados | Prova |
|---|---|---|
| Carga completa (6 partições + refined + contagens de conferência) | 16,79 MB | [`logs/ingestao.log`](evidencias/parte-2/logs/ingestao.log) |
| Backfill de 1 partição (Delhi) | 5,56 MB | [`logs/backfill.log`](evidencias/parte-2/logs/backfill.log) |

Cada partição da trusted lê o arquivo inteiro da raw (1,87 MB), porque o gzip
não é divisível nem particionado. Com 300 mil linhas isso custa menos de
US$ 0,0001 por carga; com um volume muito maior, a próxima decisão seria
particionar também a raw por cidade no momento do upload.

---

## 8. Ingestão idempotente e backfill

Motor: **Athena SQL**, orquestrado por `parte-2/scripts/ingestao.sh`.

| Etapa | Como fica idempotente |
|---|---|
| raw | upload sempre para a mesma chave (`flights/airlines_flights_data.csv.gz`): reenviar sobrescreve |
| trusted | por partição: `ALTER TABLE ... DROP IF EXISTS PARTITION` → `aws s3 rm` do prefixo → `INSERT INTO ... WHERE source_city = X` |
| refined | recalculada inteira a partir da trusted, também com DROP + rm + INSERT |

Se o processo cair no meio, rodar de novo reconstrói a partição do zero — não
existe estado intermediário que gere duplicata.

**Backfill**: `bash parte-2/scripts/ingestao.sh --particao Delhi` reprocessa só
`source_city=Delhi` (a partir da raw) e recalcula a refined.

**Idempotência da carga completa**: rodamos a carga completa duas vezes
seguidas. As duas terminaram com raw 300.153, trusted 300.153 (300.153
`id_oferta` distintos) e refined somando 300.153. Os `ingerido_em` mudaram,
ou seja, tudo foi regravado, e mesmo assim nada duplicou:
[`logs/ingestao.log`](evidencias/parte-2/logs/ingestao.log) e
[`logs/ingestao-de-novo.log`](evidencias/parte-2/logs/ingestao-de-novo.log).

**Backfill** (27/11/2026, [`logs/backfill.log`](evidencias/parte-2/logs/backfill.log), horários em UTC):

| | Antes | Depois |
|---|---|---|
| registros em `source_city=Delhi` | 61.343 | 61.343 |
| total da trusted | 300.153 | 300.153 |
| `id_oferta` distintos | 300.153 | 300.153 |
| `ingerido_em` de Delhi | 20:18:23 | 20:19:34 |
| `ingerido_em` das outras 5 partições | inalterado | inalterado |

O critério 6 do `verifica.sh` executa um backfill real a cada verificação e
reprova se a contagem mudar ou se o carimbo da partição não for atualizado.

### Regras de limpeza (raw → trusted)

- `TRIM` em textos, `flight` em maiúsculas, `stops` em minúsculas;
- `TRY_CAST` nos numéricos (valor inválido vira NULL e a linha é descartada);
- domínio: períodos, `stops` e `class` só com valores conhecidos;
- faixa: `price > 0`, `0 < duration ≤ 50 h`, `1 ≤ days_left ≤ 365`;
- origem diferente de destino;
- deduplicação pelos 11 atributos de negócio;
- enriquecimento: `qtd_escalas` (0, 1, 2) a partir de `stops`, e `ingerido_em`.

**Resultado medido: 0 linhas descartadas** (300.153 na raw → 300.153 na
trusted). A medição
[`03_raw_rejeicao_por_regra.csv`](evidencias/parte-2/medicoes/03_raw_rejeicao_por_regra.csv)
aplica cada regra isoladamente às 300.153 linhas da raw: **0 rejeições em
todas as 13 regras**. Duplicatas exatas: 0 —
[`04_raw_duplicatas_exatas.csv`](evidencias/parte-2/medicoes/04_raw_duplicatas_exatas.csv).
O dataset de origem já vem limpo. As regras ficam como contrato da camada:
qualquer carga futura com sujeira é barrada na trusted, e a diferença
raw − trusted aparece no resumo da ingestão.

---

## 9. Controle de acesso por camada — Lake Formation

| Persona | raw | trusted | refined |
|---|---|---|---|
| engenheiro (quem roda Terraform e ingestão) | total | total | total |
| `eda262-g03-cientista` | — | SELECT | SELECT |
| `eda262-g03-analista` | — | — | SELECT |

- Os 3 buckets estão registrados no Lake Formation com uma role própria
  (`eda262-g03-lakeformation-acesso`) em vez da service-linked role, para o
  `destroy` não deixar a role órfã.
- O IAM das personas libera Athena e Glue de forma ampla **de propósito**: quem
  separa as camadas é o Lake Formation.
- As configurações do Lake Formation são criadas **antes** das databases e não
  têm permissões padrão. Assim as databases não recebem o grant automático
  `IAM_ALLOWED_PRINCIPALS: ALL`, que deixaria qualquer usuário IAM ler tudo.

**Evidência** (critério 4 do `verifica.sh`, consultas reais assumindo cada role —
[`logs/verifica.log`](evidencias/parte-2/logs/verifica.log)):

| Persona → tabela | Resultado |
|---|---|
| analista → refined | permitido |
| analista → trusted | negado: "Insufficient Lake Formation permission(s): Required Describe on eda262_g03_trusted" |
| analista → raw | negado |
| cientista → refined | permitido |
| cientista → trusted | permitido |
| cientista → raw | negado |

**Conta compartilhada**: as configurações do Lake Formation valem para a conta
inteira. O Terraform soma o nosso usuário aos admins já existentes (não remove
ninguém). No `destroy`, o provider zera a lista de admins da conta — fica
registrado para quem usar a mesma conta.

### Destroy testado: o bug que encontramos

O primeiro destroy da Parte 2 **falhou** e deixou as 3 databases do Glue
órfãs. O pós-destroy deu 0/100:
[`logs/destroy-inicial.log`](evidencias/parte-2/logs/destroy-inicial.log) e
[`logs/pos-destroy-inicial.log`](evidencias/parte-2/logs/pos-destroy-inicial.log).

- **Causa**: o código declarava como recurso o grant `ALL`/`DROP` do engenheiro
  em cada database. Como o grant depende da database, o Terraform o revoga
  **antes** de apagar a database, e aí o `DeleteDatabase` falhava com
  "Insufficient Lake Formation permission(s): Required Drop".
- **Correção** (commit `7c3fcfd`): o grant deixou de ser declarado. Quem cria
  a database já recebe ALL do Lake Formation automaticamente, e nada mais o
  revoga antes da hora.
- **Recuperação**: devolvemos o DROP com `aws lakeformation grant-permissions`
  e terminamos o destroy, que removeu as 4 sobras. Pós-destroy **100/100**:
  [`logs/destroy-inicial-2.log`](evidencias/parte-2/logs/destroy-inicial-2.log) e
  [`logs/pos-destroy-inicial-3.log`](evidencias/parte-2/logs/pos-destroy-inicial-3.log).
- **Subida do zero com o código corrigido**: 44 recursos criados
  ([`logs/apply.log`](evidencias/parte-2/logs/apply.log)), `verifica.sh` 100/100
  ([`logs/verifica.log`](evidencias/parte-2/logs/verifica.log)).

---

## 10. Continuidade Parte 1 → Parte 2

A Parte 2 é a Parte 1 estendida. Na conta do grupo, os recursos que continuam
iguais **não foram recriados**: passaram do state da Parte 1 para o da Parte 2
com `terraform import` (`parte-2/scripts/migrar-da-parte-1.sh`).

| Recurso da Parte 1 | Na Parte 2 |
|---|---|
| bucket `eda262-g03-lake-trusted` (+ versionamento) | reaproveitado como camada trusted |
| workgroup `eda262-g03-athena` | reaproveitado; resultados movidos para bucket próprio, limite de 100 MB por consulta |
| database `eda262_g03_flights` + tabela `flights` (CSV) | **substituídas** por `eda262_g03_trusted.flights` (Parquet) |
| backend S3 + DynamoDB, workspace `dev` | mantidos (state em `parte-2/terraform.tfstate`) |

A database antiga não foi reaproveitada porque tinha o grant
`IAM_ALLOWED_PRINCIPALS: ALL` (e o mesmo como padrão para novas tabelas): com
ela, a trusted ficaria aberta a qualquer usuário IAM e o controle por camada
não funcionaria. Database e tabela são só metadados — recriar não tem custo.

Na conta do avaliador nada disso é necessário: `parte-2/` sobe tudo do zero.

---

## 11. Resultado da análise

Consulta na refined (`parte-2/sql/consulta_negocio_refined.sql`), idêntica à
da Parte 1:

| | Partida → chegada | Ofertas | Preço médio |
|---|---|---|---|
| maior | Night → Evening | 9.209 | 31.425,82 |
| menor | Late_Night → Late_Night | 137 | 4.288,29 |

**Novo na Parte 2 — controlando a classe** (a refined é particionada por `class`;
consideradas só combinações com ≥ 100 ofertas):

| Classe | Maior ÷ menor preço médio | Diferença absoluta |
|---|---|---|
| Economy | 2,13× | 4.264,07 |
| Business | 1,66× | 23.171,01 |

Prova: [`13_razao_por_classe.csv`](evidencias/parte-2/medicoes/13_razao_por_classe.csv)
(33 combinações em Economy e 30 em Business passam do corte de 100 ofertas) e
[`10_negocio_refined.csv`](evidencias/parte-2/medicoes/10_negocio_refined.csv)
para o maior e o menor preço médio.

A diferença de preço entre períodos **continua existindo dentro de cada classe**,
então não é só efeito de misturar Economy com Business. Ainda é associação, não
causalidade: rota, companhia, escalas e antecedência também variam entre os
períodos.

---

## 12. Histórico da Parte 1 (mantido para referência)

- Schema declarado no Terraform, sem Crawler — mantido na Parte 2 para as 3 tabelas.
- CSV sem partição na Parte 1, porque Parquet e particionamento estavam fora do
  escopo da AV1.
- Consulta da Parte 1: 24.946.485 bytes escaneados, 1.390 ms de execução no motor
  (AV1). Remedida em 27/11 com o mesmo resultado em bytes (1.107 ms) —
  medição `90_parte1_csv`.
