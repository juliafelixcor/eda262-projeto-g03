# DECISOES.md

## 1. Cenário

O projeto utiliza um conjunto de dados de passagens aéreas, com informações sobre companhia aérea, voo, cidade de origem e destino, período de partida e chegada, quantidade de escalas, classe, duração, antecedência da compra e preço.

A pergunta analítica principal definida pelo grupo é:

**O valor das passagens é influenciado pelo horário de embarque e desembarque?**

Como o dataset não possui horário exato, mas categorias de período do dia, a análise considera os campos `departure_time` e `arrival_time`.

---

## 2. Grão da tabela trusted

O grão definido para a tabela `flights` é:

**Cada registro representa uma oferta/opção de passagem aérea associada a um voo, rota, classe, período de partida, período de chegada, duração, antecedência da compra e preço.**

Essa definição foi escolhida porque um mesmo voo pode aparecer com diferentes características comerciais, como classe, antecedência e preço.

Quantidade total de registros na tabela trusted:

**300.153 registros**

---

## 3. Schema

O schema foi declarado diretamente no Terraform, sem uso de Glue Crawler.

Campos:

- index: bigint
- airline: string
- flight: string
- source_city: string
- departure_time: string
- stops: string
- arrival_time: string
- destination_city: string
- class: string
- duration: double
- days_left: int
- price: int

O campo `index` foi mantido nesta etapa porque está presente no CSV original. Sua remoção sem uma etapa de transformação causaria deslocamento das colunas durante a leitura do arquivo.

---

## 4. Formato dos dados

O dataset é armazenado em formato CSV.

O arquivo é interpretado no Glue utilizando `OpenCSVSerde`, com:

- separador: vírgula
- caractere de aspas: `"`
- escape: `\`
- primeira linha ignorada por representar o cabeçalho

Na Parte 1, o uso de CSV foi mantido porque Parquet está fora do escopo exigido nesta etapa do projeto.

---

## 5. Organização no S3

O bucket trusted utilizado é:

`eda262-g03-lake-trusted`

A organização adotada é:

eda262-g03-lake-trusted/
├── data/
│   └── airlines_flights_data.csv
└── athena-results/

A tabela do Glue aponta exclusivamente para:

`s3://eda262-g03-lake-trusted/data/`

Essa separação foi necessária porque, inicialmente, a tabela apontava para a raiz do bucket e o Athena também armazenava os resultados de consultas dentro do mesmo bucket.

Com isso, os próprios arquivos de resultado passaram a ser considerados durante a leitura da tabela, fazendo a contagem aumentar de 300.153 para valores como 300.178 e 300.181.

Após separar `/data/` de `/athena-results/`, a consulta `COUNT(*)` retornou corretamente:

**300.153 registros**

---

## 6. Métrica escolhida

A principal métrica utilizada para responder à pergunta de negócio foi:

**preço médio das passagens**

A consulta agrupa os dados pelos campos:

- `departure_time`
- `arrival_time`

Além do preço médio, foi incluído:

**COUNT(*) AS quantidade_passagens**

A quantidade de registros foi mantida porque algumas combinações possuem poucos registros e, portanto, suas médias podem ser menos representativas.

Exemplos:

- Late_Night → Afternoon: 73 registros
- Late_Night → Evening: 94 registros
- Late_Night → Night: 106 registros

Enquanto outras combinações possuem dezenas de milhares de registros, como:

- Morning → Evening: 24.289 registros
- Morning → Night: 23.680 registros
- Afternoon → Night: 20.915 registros

---

## 7. Consulta analítica

Consulta utilizada no Athena:

```sql
SELECT
    departure_time,
    arrival_time,
    COUNT(*) AS quantidade_passagens,
    ROUND(AVG(price), 2) AS preco_medio
FROM flights
GROUP BY
    departure_time,
    arrival_time
ORDER BY
    preco_medio DESC;
```
---

## 8. Resultado da análise

A combinação com maior preço médio foi:
- departure_time: Night
- arrival_time: Evening
- quantidade: 9.209
- preço médio: 31.425,82
A combinação com menor preço médio foi:
- departure_time: Late_Night
- arrival_time: Late_Night
- quantidade: 137
- preço médio: 4.288,29

A diferença entre esses extremos foi de:
27.137,53  

Os resultados indicam associação entre os períodos de embarque/desembarque e os preços observados.
Entretanto, a análise não permite afirmar causalidade, pois outros atributos do dataset também podem influenciar o preço, como classe, companhia aérea, rota, escalas e antecedência da compra.

--- 

### 9. Custo da consulta

A consulta principal no Athena apresentou:
- DataScannedInBytes: 24.946.485 bytes
- aproximadamente 24,95 MB
- EngineExecutionTimeInMillis: 1.390 ms
- TotalExecutionTimeInMillis: 1.568 ms

O custo monetário deve ser calculado com base na tarifa vigente do Amazon Athena por volume de dados escaneados.
Fórmula:
custo = volume escaneado em TB × preço vigente por TB

---

### 10. Chaves

O dataset original não possui uma chave primária explícita.
O campo index não foi tratado como chave de negócio, pois representa apenas a posição/índice do registro no arquivo original.
Para esta etapa, a tabela trusted foi modelada para análise e não para operações transacionais.

---

### 11. Particionamento

Na Parte 1, não foi aplicado particionamento.

Essa decisão segue o escopo definido pela disciplina, em que particionamento é requisito da Parte 2.