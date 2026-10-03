# Projeto de Engenharia de Dados — Grupo 03

## 1. Sobre o projeto

Este projeto foi desenvolvido para a disciplina de Engenharia de Dados da CESAR School.

O objetivo da Parte 1 é provisionar, utilizando Terraform, uma infraestrutura de Data Lake na AWS capaz de armazenar, catalogar e consultar um conjunto de dados, respondendo a uma pergunta analítica por meio do Amazon Athena.

O conjunto de dados escolhido contém informações relacionadas a passagens aéreas, incluindo companhia aérea, voo, cidade de origem e destino, período de partida e chegada, classe, duração, antecedência da compra e preço.

---

## 2. Pergunta de negócio

A pergunta analítica escolhida pelo grupo foi:

> **O valor das passagens é influenciado pelo horário de embarque e desembarque?**

Como o conjunto de dados não possui horários exatos, mas períodos do dia, a análise considera principalmente os campos:

- `departure_time`
- `arrival_time`
- `price`

Os possíveis valores de período incluem categorias como:

- `Early_Morning`
- `Morning`
- `Afternoon`
- `Evening`
- `Night`
- `Late_Night`

O objetivo da consulta é comparar o preço médio das passagens entre diferentes combinações de períodos de partida e chegada.

---

## 3. Arquitetura

A arquitetura da Parte 1 utiliza os seguintes serviços da AWS:

- Amazon S3;
- AWS Glue Data Catalog;
- Amazon Athena;
- Amazon DynamoDB;
- Terraform para provisionamento da infraestrutura.

Fluxo simplificado:

```text
Dataset CSV
    |
    v
Amazon S3
    |
    v
Glue Data Catalog
    |
    v
Amazon Athena
    |
    v
Consulta analítica
    |
    v
Resultado + custo da consulta
```

O Terraform utiliza um backend remoto com:

- S3 para armazenamento do estado;
- DynamoDB para controle de lock do state;
- workspace `dev`.

### Imagem da arquitetura

> **Adicionar aqui a imagem/diagrama da arquitetura.**

---

## 4. Estrutura do repositório

A estrutura principal do projeto é:

```text
eda262-projeto-g03/
│
├── parte-1/
│   ├── backend.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── variables.tf
│   │
│   └── modules/
│       └── data-lake/
│           ├── main.tf
│           ├── outputs.tf
│           └── variables.tf
│
├── verificacao/
│   └── verifica.sh
│
├── DECISOES.md
│
└── README.md
```

O módulo `data-lake` contém os principais recursos da infraestrutura utilizados na Parte 1.

---

## 5. Região AWS

A região utilizada pelo projeto é:

```text
us-east-1
```

Essa configuração está declarada no Terraform por meio da variável `aws_region`.

---

## 6. Pré-requisitos

Antes de executar o projeto, é necessário possuir:

- Terraform instalado;
- AWS CLI instalada;
- credenciais AWS válidas;
- acesso aos serviços utilizados pelo projeto;
- Git, caso o projeto seja obtido por meio do repositório.

É possível verificar as instalações com:

```bash
terraform --version
```

e:

```bash
aws --version
```

---

## 7. Configuração das credenciais AWS

As credenciais AWS devem estar configuradas na máquina que executará o projeto.

Caso ainda não estejam configuradas:

```bash
aws configure
```

Será necessário informar:

```text
AWS Access Key ID
AWS Secret Access Key
Default region
Default output format
```

Para verificar se a autenticação está funcionando:

```bash
aws sts get-caller-identity
```

A execução deve retornar as informações da conta AWS autenticada.

### Evidência

> <img width="535" height="118" alt="image" src="https://github.com/user-attachments/assets/0795f721-d525-4a88-985d-c93fe3236ed0" />

---

## 8. Backend remoto do Terraform

O Terraform utiliza backend remoto para armazenamento do state.

O backend é composto por:

- bucket S3 para armazenamento do `terraform.tfstate`;
- tabela DynamoDB utilizada para controle de lock;
- criptografia do state habilitada.

O arquivo responsável por essa configuração é:

```text
parte-1/backend.tf
```

O backend deve existir antes da execução do `terraform init`.

Após clonar o projeto em uma nova máquina, entre na pasta:

```bash
cd parte-1
```

e execute:

```bash
terraform init
```

O `terraform init` precisa ser realizado em cada máquina que utilizar o projeto, pois ele inicializa localmente os providers e conecta aquela instalação ao backend remoto.

---

## 9. Workspace

O workspace utilizado pelo projeto é:

```text
dev
```

Para verificar os workspaces disponíveis:

```bash
terraform workspace list
```

Caso o workspace já exista, selecione:

```bash
terraform workspace select dev
```

Caso seja a primeira execução e ele ainda não exista:

```bash
terraform workspace new dev
```

Para verificar o workspace atual:

```bash
terraform workspace show
```

### Evidência

> <img width="757" height="52" alt="image" src="https://github.com/user-attachments/assets/a0a1301c-5892-43a0-b182-a298cddb3fbc" />

---

## 10. Validação da configuração Terraform

Antes de realizar qualquer alteração na infraestrutura, é recomendado formatar e validar os arquivos.

```bash
terraform fmt
terraform validate
```

O resultado esperado é:

```text
Success! The configuration is valid.
```

### Evidência

> **Adicionar aqui imagem do `terraform validate`.**

---

## 11. Visualização do plano

Antes de criar ou modificar recursos:

```bash
terraform plan
```

Esse comando permite visualizar quais recursos serão:

- adicionados;
- modificados;
- destruídos.

O plano deve ser analisado antes da execução do `terraform apply`.

---

## 12. Provisionamento da infraestrutura

Para criar a infraestrutura:

```bash
terraform apply
```

Após revisar o plano apresentado pelo Terraform, confirme digitando:

```text
yes
```

A infraestrutura da Parte 1 inclui:

- bucket S3 trusted;
- versionamento do bucket;
- Glue Database;
- Glue Table;
- Athena Workgroup.

Os recursos utilizam o padrão de nomenclatura:

```text
eda262-g03-<recurso>
```

e as tags:

```text
turma   = eda262
grupo   = g03
projeto = engenharia-de-dados
```

### Evidência

> **Adicionar aqui imagem do `terraform apply` concluído.**

---

## 13. Outputs do Terraform

Após o provisionamento, os principais recursos podem ser consultados com:

```bash
terraform output
```

No projeto foram obtidos:

```text
athena_workgroup_name = "eda262-g03-athena"
glue_database_name    = "eda262_g03_flights"
glue_table_name       = "flights"
trusted_bucket_name   = "eda262-g03-lake-trusted"
```

### Evidência

> **Adicionar aqui imagem do `terraform output`.**

---

## 14. Organização dos dados no S3

O bucket utilizado para os dados trusted é:

```text
eda262-g03-lake-trusted
```

Sua organização é:

```text
eda262-g03-lake-trusted/
│
├── data/
│   └── airlines_flights_data.csv
│
└── athena-results/
```

O diretório `/data/` é utilizado exclusivamente pelos dados consultados pela tabela do Glue.

O diretório `/athena-results/` é utilizado para armazenar os resultados das consultas do Athena.

Essa separação evita que arquivos gerados pelo Athena sejam interpretados como registros pertencentes ao dataset.

---

## 15. Upload do dataset

O dataset utilizado é:

```text
airlines_flights_data.csv
```

Para enviar o arquivo ao bucket:

```bash
aws s3 cp CAMINHO_DO_ARQUIVO/airlines_flights_data.csv s3://eda262-g03-lake-trusted/data/
```

Exemplo no Windows:

```powershell
aws s3 cp "C:\Users\USUARIO\Downloads\airlines_flights_data.csv" s3://eda262-g03-lake-trusted/data/
```

Para verificar o upload:

```bash
aws s3 ls s3://eda262-g03-lake-trusted/data/
```

### Evidência

> **Adicionar aqui imagem do upload do CSV e do `aws s3 ls`.**

---

## 16. Glue Data Catalog

O banco criado no Glue é:

```text
eda262_g03_flights
```

A tabela é:

```text
flights
```

O schema da tabela é declarado diretamente no Terraform, sem utilização de Glue Crawler.

As colunas são:

```text
index
airline
flight
source_city
departure_time
stops
arrival_time
destination_city
class
duration
days_left
price
```

O arquivo é interpretado como CSV utilizando `OpenCSVSerde`.

A primeira linha do arquivo é ignorada por representar o cabeçalho.

---

## 17. Validação do número de registros

Antes de executar a consulta analítica, foi realizada uma consulta para validar o número de registros:

```sql
SELECT COUNT(*) AS total_registros
FROM flights;
```

Resultado:

```text
300153
```

O valor corresponde à quantidade esperada de registros do dataset.

### Evidência

> **Adicionar aqui imagem do resultado `300153`.**

---

## 18. Consulta analítica

A consulta utilizada para responder à pergunta de negócio foi:

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

A consulta calcula:

- quantidade de passagens por combinação;
- preço médio por combinação de período de partida e chegada.

A quantidade de registros também foi incluída para permitir avaliar a representatividade de cada preço médio.

---

## 19. Resultado da análise

A combinação que apresentou o maior preço médio foi:

```text
Departure time: Night
Arrival time: Evening
Quantidade de registros: 9.209
Preço médio: 31.425,82
```

A combinação com menor preço médio foi:

```text
Departure time: Late_Night
Arrival time: Late_Night
Quantidade de registros: 137
Preço médio: 4.288,29
```

A diferença entre os dois valores médios foi:

```text
27.137,53
```

Os resultados mostram que os preços médios variam entre as diferentes combinações de períodos de embarque e desembarque.

Entretanto, essa análise evidencia uma associação e não permite afirmar causalidade. Outros atributos presentes no conjunto de dados também podem influenciar o preço, como:

- companhia aérea;
- rota;
- classe;
- quantidade de escalas;
- duração;
- antecedência da compra.

Além disso, algumas combinações possuem quantidade significativamente menor de registros, razão pela qual a quantidade de passagens foi mantida junto ao cálculo da média.

### Evidência

> **Adicionar aqui imagem da tabela completa retornada pelo Athena.**

---

## 20. Métricas da consulta Athena

A consulta principal apresentou as seguintes métricas:

```text
DataScannedInBytes: 24.946.485 bytes
EngineExecutionTimeInMillis: 1.390 ms
TotalExecutionTimeInMillis: 1.568 ms
```

O volume total escaneado corresponde a aproximadamente:

```text
24,95 MB
```

Esse valor é utilizado para a medição de custo da consulta.

O cálculo monetário deve utilizar a tarifa vigente do Amazon Athena para a região e modalidade utilizadas no momento da execução.

Fórmula:

```text
custo = volume escaneado em TB × preço do Athena por TB
```

### Evidência

> <img width="821" height="377" alt="image" src="https://github.com/user-attachments/assets/cea12f33-2baa-47f5-8537-99f159f2b472" />

---

## 21. Principais decisões de engenharia

As principais decisões tomadas durante o desenvolvimento estão documentadas no arquivo:

```text
DECISOES.md
```

Entre elas:

- definição do grão da tabela;
- declaração manual do schema;
- formato utilizado;
- escolha da métrica `AVG(price)`;
- utilização de `COUNT(*)`;
- organização do bucket S3;
- ausência de particionamento na Parte 1;
- medição do volume de dados escaneados;
- análise do custo da consulta.

---

## 22. Verificação

O projeto possui o script:

```text
verificacao/verifica.sh
```

Ele deve verificar os principais critérios da infraestrutura e apresentar resultados no formato:

```text
PASSA
```

ou:

```text
FALHA
```

Entre os itens a serem verificados estão:

- existência do bucket trusted;
- existência do Glue Database;
- existência da Glue Table;
- existência do Athena Workgroup;
- existência do dataset no S3;
- disponibilidade dos recursos necessários para execução da consulta.

Para executar:

```bash
bash verificacao/verifica.sh
```

### Evidência

> **Adicionar aqui imagem da execução completa do `verifica.sh`.**

---

## 23. Reprodução em outra máquina

Para reproduzir o projeto em outra máquina:

```bash
git clone <URL_DO_REPOSITORIO>
```

Entrar na pasta:

```bash
cd eda262-projeto-g03/parte-1
```

Inicializar o Terraform:

```bash
terraform init
```

Selecionar o workspace:

```bash
terraform workspace select dev
```

Validar:

```bash
terraform validate
```

Visualizar o plano:

```bash
terraform plan
```

Criar a infraestrutura:

```bash
terraform apply
```

Depois do provisionamento, realizar o upload do dataset:

```bash
aws s3 cp CAMINHO_DO_DATASET/airlines_flights_data.csv s3://eda262-g03-lake-trusted/data/
```

Após isso, as consultas podem ser executadas utilizando o Athena Workgroup:

```text
eda262-g03-athena
```

e o banco:

```text
eda262_g03_flights
```

---

## 24. Destruição da infraestrutura

Ao final da execução, os recursos provisionados pelo Terraform devem ser removidos.

Dentro da pasta:

```text
parte-1/
```

execute:

```bash
terraform destroy
```

Revise o plano e confirme:

```text
yes
```

Após a execução, deve ser confirmado que os recursos gerenciados pelo Terraform foram removidos corretamente e que não existem recursos órfãos.

> **Observação:** objetos existentes em buckets S3 podem impedir a exclusão do bucket. Antes do teste final de destroy, deve-se garantir que o fluxo definido pelo grupo permita a remoção limpa da infraestrutura.

### Evidência

> **Adicionar aqui imagem do `terraform destroy` concluído.**

---

## 25. Fluxo completo de execução

O fluxo completo do projeto é:

```text
Configurar AWS CLI
        ↓
terraform init
        ↓
terraform workspace select dev
        ↓
terraform validate
        ↓
terraform plan
        ↓
terraform apply
        ↓
Upload do dataset para o S3
        ↓
Validação do COUNT(*)
        ↓
Execução da consulta analítica
        ↓
Medição dos bytes escaneados
        ↓
Execução do verifica.sh
        ↓
terraform destroy
```

---

## 26. Conclusão

A infraestrutura implementada permite armazenar o conjunto de dados no Amazon S3, disponibilizar seu schema através do AWS Glue Data Catalog e executar consultas analíticas utilizando o Amazon Athena.

A consulta desenvolvida permitiu identificar diferenças relevantes nos preços médios entre os diferentes períodos de partida e chegada.

A infraestrutura foi provisionada utilizando Terraform e organizada de forma modular, permitindo sua reprodução em outras máquinas e contas AWS.

O projeto também registra as decisões de engenharia e métricas da consulta para permitir avaliar tanto o comportamento dos dados quanto o custo da solução.
