# DECISOES.md — Grupo 03

Decisões de engenharia do Data Lake de passagens aéreas, **Partes 1 e 2**.
Cada decisão traz o número medido que a sustenta. Medições feitas em
26/11/2026 na conta 325583868777 (us-east-1), workgroup `eda262-g03-athena`.

## Resumo das decisões

| Decisão | Escolha | Número que comprova |
|---|---|---|
| Grão (trusted) | 1 linha = 1 oferta de passagem (observação de preço) | 300.153 linhas = 300.153 `id_oferta` distintos; 1.555 combinações voo/rota/classe/dia/período aparecem com preços diferentes |
| Grão (refined) | `class` × `departure_time` × `arrival_time` | 71 linhas (36 Economy + 35 Business) resumem 300.153 ofertas |
| Chave | `id_oferta` (surrogate vindo do `index` da fonte) | 0 duplicatas; chave natural candidata colide em 1.555 grupos |
| Partição | trusted por `source_city`; refined por `class` | filtro por cidade: 378,26 KB → 78,25 KB (−79%); filtro por classe: 1.429 B → 905 B |
| Formato | raw CSV gzip; trusted e refined Parquet Snappy | mesma consulta: CSV 24,95 MB → Parquet 606,06 KB (−97,6%) → refined 1,43 KB |
| Custo | meta ≤ 1 MiB escaneado na consulta de negócio | medido: **1.429 bytes** (0,14% da meta) |
| Idempotência | sobrescrita por partição (DROP + rm + INSERT) | backfill de Delhi: 61.343 → 61.343 registros; total 300.153 → 300.153 |
| Acesso | 1 database por camada + Lake Formation | analista negado na trusted/raw ("Insufficient Lake Formation permission(s)") e liberado na refined |

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
perderia informação de preço. Duplicatas exatas (todos os atributos iguais):
**0**.

### refined
**1 linha = `class` × `departure_time` × `arrival_time`**: exatamente o grão
da pergunta de negócio, com a classe junto porque é o principal fator de
confusão do preço (ver seção 9).

- **71 linhas** (36 Economy + 35 Business — uma combinação não ocorre em Business).
- Guarda `qtd_passagens` e `soma_preco` além de `preco_medio`: assim a média
  geral é recomposta exatamente (`SUM(soma_preco) / SUM(qtd_passagens)`) sem
  voltar à trusted. Verificado: o resultado na refined é idêntico ao da trusted
  e ao da Parte 1 (Night→Evening = 31.425,82 nas três).

---

## 4. Chaves

| Camada | Chave | Evidência |
|---|---|---|
| trusted | `id_oferta` (BIGINT, vem do `index` do CSV) | 300.153 linhas, 300.153 distintos (o `verifica.sh` checa a cada execução) |
| trusted | chave de deduplicação: os 11 atributos de negócio | 0 duplicatas removidas |
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

- **Volume equilibrado**: a maior partição tem 1,6× a menor. 6 arquivos
  Parquet, 2,73 MB no total (Delhi: 564 KB).
- **Unidade natural de carga e de backfill**: o dataset não tem data; a cidade
  de origem funciona como "lote" (o feed de cada aeroporto). Reprocessar uma
  cidade não toca nas outras cinco.
- **Pruning medido**: `AVG(price)` em todas as cidades escaneia 378,26 KB; com
  `WHERE source_city = 'Delhi'`, 78,25 KB (**−79%**).

Alternativas descartadas:
- `departure_time`: é a coluna agrupada pela pergunta, então a consulta lê
  todas as partições de qualquer jeito (zero pruning), e `Late_Night` teria só
  **1.306 linhas** (0,4% do total) — partição minúscula.
- data de ingestão: coluna sintética, sem significado de negócio e sem pruning
  útil para a pergunta.
- partições mais finas (cidade × companhia = até 36): arquivos ainda menores;
  com 2,73 MB no total, só aumentaria o overhead de arquivos pequenos.

### refined — `class`
A refined tem 71 linhas e 5,4 KB; a partição existe para a análise por classe:
a consulta só de Economy escaneia **905 B** contra 1.429 B da consulta geral.

---

## 6. Formato

| Onde | Formato | Tamanho em disco | Bytes escaneados pela consulta de negócio |
|---|---|---|---|
| Parte 1 (trusted) | CSV | 24,95 MB | **24.946.485 B** |
| Parte 2 raw | CSV gzip | 1,87 MB | 1.871.576 B |
| Parte 2 trusted | Parquet Snappy | 2,73 MB | **606.056 B** (−97,6% vs Parte 1) |
| Parte 2 refined | Parquet Snappy | 5,4 KB | **1.429 B** (−99,99% vs Parte 1) |

- **raw em CSV gzip**: guarda o arquivo como veio, 13× menor que o CSV puro.
  Gzip não é divisível nem colunar: qualquer consulta na raw lê o arquivo todo
  (1,87 MB). Por isso a raw não é camada de consulta.
- **trusted em Parquet**: em disco fica até maior que o gzip (2,73 MB vs
  1,87 MB), mas é colunar — a consulta de negócio lê só `departure_time`,
  `arrival_time` e `price`, e `COUNT(*)` é respondido pelos metadados do Parquet
  (**0 bytes** escaneados).
- **Snappy**: compressão rápida e padrão de mercado para Parquet; a diferença de
  tamanho para gzip é irrelevante neste volume.

---

## 7. Custo

### Meta de custo (declarada)

> **A consulta da pergunta de negócio escaneia no máximo 1 MiB (1.048.576 bytes).**

**Cumprida:** a consulta na refined escaneou **1.429 bytes** (QueryExecutionId
registrado na saída do `verifica.sh`). O valor oscila alguns bytes entre cargas
(ex.: ~1,42 KB após um backfill), porque os arquivos Parquet da refined são
regravados; a folga para a meta é de mais de 700×. O critério 7 do `verifica.sh` roda a
consulta e reprova se passar da meta ou se o resultado divergir da trusted.

Proteção extra: o workgroup tem `bytes_scanned_cutoff_per_query = 100 MB`;
nenhuma consulta do grupo passa disso.

### Custo monetário

Athena cobra **US$ 5,00 por TB** escaneado, arredondado para cima ao MB, com
**mínimo de 10 MB por consulta**.

| Consulta | Bytes escaneados | Bytes cobrados | Custo por consulta |
|---|---|---|---|
| Parte 1 — CSV | 24.946.485 | 25 MB | US$ 0,000125 |
| Parte 2 — trusted Parquet | 606.056 | 10 MB (mínimo) | US$ 0,000050 |
| Parte 2 — refined | 1.429 | 10 MB (mínimo) | US$ 0,000050 |

Leitura honesta dos números: o volume escaneado caiu 99,99%, mas o custo cobrado
caiu 60%, porque as duas consultas da Parte 2 ficam abaixo do mínimo de 10 MB.
O ganho cresce com o volume: a refined tem no máximo 72 linhas (2 classes × 6 × 6
períodos) independentemente de quantas ofertas existam, enquanto o CSV da Parte 1
cresce linearmente com os dados.

### Custo da ingestão (medido)

| Execução | Bytes escaneados |
|---|---|
| Carga completa (6 partições + refined + contagens de conferência) | 16,79 MB |
| Backfill de 1 partição (Delhi) | 5,56 MB |

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

Evidência (execução de 26/11/2026):

| | Antes | Depois |
|---|---|---|
| registros em `source_city=Delhi` | 61.343 | 61.343 |
| total da trusted | 300.153 | 300.153 |
| `id_oferta` distintos | 300.153 | 300.153 |
| `ingerido_em` de Delhi | 12:42:36 | 12:56:48 |
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
trusted). O dataset de origem já vem limpo — perfilamos 0 nulos e 0 duplicatas
exatas. As regras ficam como contrato da camada: qualquer carga futura com
sujeira é barrada na trusted, e a diferença raw − trusted aparece no resumo da
ingestão.

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

**Evidência** (critério 4 do `verifica.sh`, consultas reais assumindo cada role):

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

A diferença de preço entre períodos **continua existindo dentro de cada classe**,
então não é só efeito de misturar Economy com Business. Ainda é associação, não
causalidade: rota, companhia, escalas e antecedência também variam entre os
períodos.

---

## 12. Histórico da Parte 1 (mantido para referência)

- Schema declarado no Terraform, sem Crawler — mantido na Parte 2 para as 3 tabelas.
- CSV sem partição na Parte 1, porque Parquet e particionamento estavam fora do
  escopo da AV1.
- Consulta da Parte 1: 24.946.485 bytes escaneados, 1.390 ms de execução no motor.
