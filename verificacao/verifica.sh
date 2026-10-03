#!/usr/bin/env bash

set -u

REGION="us-east-1"
BUCKET="eda262-g03-lake-trusted"
GLUE_DATABASE="eda262_g03_flights"
GLUE_TABLE="flights"
ATHENA_WORKGROUP="eda262-g03-athena"
DATASET_KEY="data/airlines_flights_data.csv"

FALHAS=0

passa() {
  echo "PASSA - $1"
}

falha() {
  echo "FALHA - $1"
  FALHAS=$((FALHAS + 1))
}

echo "=========================================="
echo "Verificação do Projeto - Grupo 03"
echo "=========================================="

echo
echo "1. Verificando bucket S3..."

if aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  2>/dev/null; then
  passa "Bucket trusted existe"
else
  falha "Bucket trusted não existe ou não está acessível"
fi

echo
echo "2. Verificando dataset no S3..."

if aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$DATASET_KEY" \
  --region "$REGION" \
  >/dev/null 2>&1; then
  passa "Dataset existe em s3://$BUCKET/$DATASET_KEY"
else
  falha "Dataset não encontrado em s3://$BUCKET/$DATASET_KEY"
fi

echo
echo "3. Verificando Glue Database..."

if aws glue get-database \
  --name "$GLUE_DATABASE" \
  --region "$REGION" \
  >/dev/null 2>&1; then
  passa "Glue Database existe"
else
  falha "Glue Database não existe"
fi

echo
echo "4. Verificando Glue Table..."

if aws glue get-table \
  --database-name "$GLUE_DATABASE" \
  --name "$GLUE_TABLE" \
  --region "$REGION" \
  >/dev/null 2>&1; then
  passa "Glue Table existe"
else
  falha "Glue Table não existe"
fi

echo
echo "5. Verificando Athena Workgroup..."

if aws athena get-work-group \
  --work-group "$ATHENA_WORKGROUP" \
  --region "$REGION" \
  >/dev/null 2>&1; then
  passa "Athena Workgroup existe"
else
  falha "Athena Workgroup não existe"
fi

echo
echo "=========================================="

if [ "$FALHAS" -eq 0 ]; then
  echo "PASSA - Todos os critérios foram atendidos"
  exit 0
else
  echo "FALHA - $FALHAS critério(s) não atendido(s)"
  exit 1
fi