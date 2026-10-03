#!/usr/bin/env bash

set -uo pipefail

TFDIR="${TFDIR:-../parte-1}"
REGIAO="${AWS_REGION:-us-east-1}"
DECISOES="${DECISOES:-../DECISOES.md}"

BUCKET="eda262-g03-lake-trusted"
GLUE_DATABASE="eda262_g03_flights"
GLUE_TABLE="flights"
ATHENA_WORKGROUP="eda262-g03-athena"
DATASET_KEY="data/airlines_flights_data.csv"

POS=0
[ "${1:-}" = "--pos-destroy" ] && POS=1

G=$'\e[32m'
R=$'\e[31m'
D=$'\e[2m'
B=$'\e[1m'
X=$'\e[0m'

notas=0
total=0

linha() {
  printf '%s\n' "----------------------------------------------------------------"
}

pass() {
  notas=$((notas+$2))
  total=$((total+$2))
  printf "${G}PASSA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"
}

fail() {
  total=$((total+$2))
  printf "${R}FALHA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"
}

info() {
  printf "${D}       %s${X}\n" "$1"
}

tfout() {
  terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null
}

# ============================================================
# Pós-destroy
# ============================================================

if [ "$POS" = "1" ]; then
  echo "${B}Critério 6 — destroy limpo${X}"
  linha

  orfao="$(aws s3 ls --region "$REGIAO" 2>/dev/null | grep "$BUCKET" || true)"

  if [ -z "$orfao" ]; then
    pass "6" 15 "nenhum bucket órfão encontrado."
  else
    fail "6" 15 "bucket órfão encontrado:"
    echo "$orfao"
  fi

  linha
  printf "${B}Critério 6: %s/15%%${X}\n" "$notas"
  exit 0
fi

echo "${B}Projeto Engenharia de Dados — Grupo 03${X}"
linha

# ============================================================
# Critério 0 — módulo + backend remoto
# ============================================================

echo "${B}Critério 0 — módulo + backend remoto${X}"

if ! grep -rqE '^\s*module\s+"' "$TFDIR"/*.tf 2>/dev/null; then
  fail "0" 0 "não foi encontrado bloco module na raiz."
  exit 2
fi

if [ ! -d "$TFDIR/modules" ]; then
  fail "0" 0 "não foi encontrada a pasta modules/."
  exit 2
fi

if ! grep -rqE 'backend\s+"s3"' "$TFDIR"/*.tf 2>/dev/null; then
  fail "0" 0 "backend S3 não encontrado."
  exit 2
fi

printf "${G}OK${X}     [0] módulo, backend S3 e pasta modules/ presentes\n"
linha

# ============================================================
# Critério 1 — plan limpo
# ============================================================

echo "${B}Critério 1 — terraform plan limpo${X}"

terraform -chdir="$TFDIR" plan -detailed-exitcode >/tmp/projeto-plan.txt 2>&1
rc=$?

if [ "$rc" = "0" ]; then
  pass "1" 20 "No changes — infraestrutura sincronizada."
elif [ "$rc" = "2" ]; then
  fail "1" 20 "o plan quer alterar recursos."
  grep -E '# .* will be| will be (created|destroyed|replaced)' /tmp/projeto-plan.txt | head -6
else
  fail "1" 20 "erro ao executar terraform plan."
  tail -5 /tmp/projeto-plan.txt
fi

linha

# ============================================================
# Critério 2 — S3 + dataset
# ============================================================

echo "${B}Critério 2 — bucket S3 e dataset${X}"

if aws s3api head-bucket \
  --bucket "$BUCKET" \
  --region "$REGIAO" \
  2>/dev/null; then
  pass "2" 10 "bucket trusted existe."
else
  fail "2" 10 "bucket trusted não existe."
fi

if aws s3api head-object \
  --bucket "$BUCKET" \
  --key "$DATASET_KEY" \
  --region "$REGIAO" \
  >/dev/null 2>&1; then
  pass "2b" 10 "dataset encontrado no S3."
else
  fail "2b" 10 "dataset não encontrado no S3."
fi

linha

# ============================================================
# Critério 3 — Glue
# ============================================================

echo "${B}Critério 3 — Glue Data Catalog${X}"

if aws glue get-database \
  --name "$GLUE_DATABASE" \
  --region "$REGIAO" \
  >/dev/null 2>&1; then
  pass "3" 10 "Glue Database existe."
else
  fail "3" 10 "Glue Database não existe."
fi

if aws glue get-table \
  --database-name "$GLUE_DATABASE" \
  --name "$GLUE_TABLE" \
  --region "$REGIAO" \
  >/dev/null 2>&1; then
  pass "3b" 10 "Glue Table existe."
else
  fail "3b" 10 "Glue Table não existe."
fi

linha

# ============================================================
# Critério 4 — Athena
# ============================================================

echo "${B}Critério 4 — Athena Workgroup${X}"

if aws athena get-work-group \
  --work-group "$ATHENA_WORKGROUP" \
  --region "$REGIAO" \
  >/dev/null 2>&1; then
  pass "4" 10 "Athena Workgroup existe."
else
  fail "4" 10 "Athena Workgroup não existe."
fi

linha

# ============================================================
# Critério 5 — outputs
# ============================================================

echo "${B}Critério 5 — outputs do Terraform${X}"

faltou=""

for o in trusted_bucket_name glue_database_name glue_table_name athena_workgroup_name; do
  [ -z "$(tfout "$o")" ] && faltou="$faltou $o"
done

if [ -z "$faltou" ]; then
  pass "5" 10 "outputs principais presentes."
else
  fail "5" 10 "outputs ausentes:$faltou"
fi

linha

# ============================================================
# Critério 7 — DECISOES.md
# ============================================================

echo "${B}Critério 7 — DECISOES.md${X}"

if [ -f "$DECISOES" ]; then
  info "DECISOES.md encontrado."
  pass "7" 10 "arquivo de decisões presente."
else
  fail "7" 10 "DECISOES.md não encontrado."
fi

linha

echo "${B}Resultado automático: $notas / $total pontos-percentuais${X}"

info "Após o terraform destroy, execute:"
info "./verifica.sh --pos-destroy"
