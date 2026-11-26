#!/usr/bin/env bash
# ============================================================
# Migração única Parte 1 -> Parte 2 (somente na conta do grupo)
#
# A Parte 2 continua a infraestrutura da Parte 1. Em vez de destruir e
# recriar, os recursos que seguem iguais passam do state da Parte 1 para
# o state da Parte 2:
#
#   bucket   eda262-g03-lake-trusted   -> vira a camada trusted
#   versionamento do bucket trusted    -> mantido
#   workgroup eda262-g03-athena        -> mantido (só muda o local dos resultados)
#
# A database eda262_g03_flights NÃO é reaproveitada: foi criada com o grant
# padrão IAM_ALLOWED_PRINCIPALS:ALL, que deixaria a trusted aberta e anularia
# o controle por camada do Lake Formation. Ela e a tabela antiga são
# destruídas pelo próprio Terraform da Parte 1.
#
# Na conta do avaliador este script NÃO é necessário: tudo sobe do zero.
#
#   bash parte-2/scripts/migrar-da-parte-1.sh
# ============================================================

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P1="$RAIZ/parte-1"
P2="$RAIZ/parte-2"
WORKSPACE="${WORKSPACE:-dev}"
CONTA_ID="$(aws sts get-caller-identity --query Account --output text | tr -d '\r')"

declare -A MAPA=(
  ["module.data_lake.aws_s3_bucket.trusted"]='module.data_lake.aws_s3_bucket.camada["trusted"]|eda262-g03-lake-trusted'
  ["module.data_lake.aws_s3_bucket_versioning.trusted"]='module.data_lake.aws_s3_bucket_versioning.camada["trusted"]|eda262-g03-lake-trusted'
  ["module.data_lake.aws_athena_workgroup.flights"]='module.data_lake.aws_athena_workgroup.this|eda262-g03-athena'
)

workspace() {
  terraform -chdir="$1" workspace select "$WORKSPACE" 2>/dev/null \
    || terraform -chdir="$1" workspace new "$WORKSPACE"
}

echo "== conta $CONTA_ID, workspace $WORKSPACE"

echo "== 1/4 init das duas pastas"
terraform -chdir="$P1" init -input=false >/dev/null
terraform -chdir="$P2" init -input=false >/dev/null
workspace "$P1"
workspace "$P2"

ESTADO_P1="$(terraform -chdir="$P1" state list)"
ESTADO_P2="$(terraform -chdir="$P2" state list)"

echo "== 2/4 import na Parte 2"
for origem in "${!MAPA[@]}"; do
  destino="${MAPA[$origem]%%|*}"
  id="${MAPA[$origem]##*|}"
  if grep -qxF "$destino" <<<"$ESTADO_P2"; then
    echo "   já está na Parte 2: $destino"
  else
    terraform -chdir="$P2" import -input=false "$destino" "$id"
  fi
done

echo "== 3/4 remove do state da Parte 1 (sem destruir na AWS)"
for origem in "${!MAPA[@]}"; do
  if grep -qxF "$origem" <<<"$ESTADO_P1"; then
    terraform -chdir="$P1" state rm "$origem"
  else
    echo "   já não está na Parte 1: $origem"
  fi
done

echo "== 4/4 destroy do que sobrou da Parte 1 (database/tabela do Glue)"
terraform -chdir="$P1" plan -destroy -input=false -no-color -out="$P1/destroy.tfplan" >"$P1/destroy.txt"
alvos="$(terraform -chdir="$P1" show -no-color "$P1/destroy.tfplan" | grep -E '^\s+# .* will be destroyed' || true)"
echo "$alvos"
if grep -vqE 'aws_glue_catalog_(database|table)' <<<"$alvos"; then
  echo "ABORTADO: o destroy da Parte 1 incluiria algo além do Glue." >&2
  rm -f "$P1/destroy.tfplan" "$P1/destroy.txt"
  exit 1
fi
terraform -chdir="$P1" apply -input=false "$P1/destroy.tfplan"
rm -f "$P1/destroy.tfplan" "$P1/destroy.txt"

echo "== limpeza: CSV da Parte 1 que ficava na trusted (a raw passa a guardar o bruto)"
aws s3 rm "s3://eda262-g03-lake-trusted/data/" --recursive --only-show-errors

echo
echo "Migração concluída. Próximo passo:"
echo "  terraform -chdir=parte-2 plan    # bucket e workgroup aparecem como 'update in-place'"
echo "  terraform -chdir=parte-2 apply"
