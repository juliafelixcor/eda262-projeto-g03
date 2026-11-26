#!/usr/bin/env bash
# ============================================================
# Ingestão idempotente do Data Lake: raw -> trusted -> refined
# (motor: Athena SQL)
#
#   bash parte-2/scripts/ingestao.sh                   carga completa
#   bash parte-2/scripts/ingestao.sh --particao Delhi  backfill de 1 partição
#
# Idempotência: cada partição da trusted é SOBRESCRITA
#   1. ALTER TABLE ... DROP IF EXISTS PARTITION   (catálogo)
#   2. aws s3 rm s3://.../source_city=<cidade>/   (dados)
#   3. INSERT INTO ... WHERE source_city = <cidade>
# A refined é recalculada inteira a partir da trusted, do mesmo jeito.
# Rodar o script N vezes produz exatamente o mesmo conteúdo.
# ============================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/athena.sh"

uso() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

PARTICAO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --particao) PARTICAO="${2:-}"; shift 2 || { uso; exit 1; } ;;
    -h|--help)  uso; exit 0 ;;
    *)          erro "argumento desconhecido: $1"; uso; exit 1 ;;
  esac
done

falhou() {
  erro "$1"
  [ -n "$ATHENA_ERRO" ] && info "Athena: $ATHENA_ERRO"
  exit 1
}

contar_particao() {
  athena_exec "SELECT COUNT(*) FROM $TABELA_TRUSTED WHERE source_city = '$1'" \
    || falhou "falha ao contar a partição $1"
  athena_valor
}

carregar_particao_trusted() {
  local cidade="$1" sql

  athena_exec "ALTER TABLE $TABELA_TRUSTED DROP IF EXISTS PARTITION (source_city = '$cidade')" \
    || falhou "falha ao remover a partição source_city=$cidade do catálogo"

  aws_ s3 rm "s3://$BUCKET_TRUSTED/flights/source_city=$cidade/" --recursive --only-show-errors \
    || falhou "falha ao limpar s3://$BUCKET_TRUSTED/flights/source_city=$cidade/"

  sql="$(sql_arquivo trusted_carga_particao.sql | sed "s/{{CIDADE}}/$cidade/g")"
  athena_exec "$sql" || falhou "falha no INSERT da partição source_city=$cidade"

  ok "trusted source_city=$cidade  ($(fmt_bytes "$ATHENA_BYTES") escaneados na raw)"
}

recarregar_refined() {
  local classe

  for classe in $(aws_ glue get-partitions \
                    --database-name "$DB_REFINED" --table-name preco_por_periodo \
                    --query 'Partitions[].Values[0]' --output text); do
    athena_exec "ALTER TABLE $TABELA_REFINED DROP IF EXISTS PARTITION (class = '$classe')" \
      || falhou "falha ao remover a partição class=$classe"
  done

  aws_ s3 rm "s3://$BUCKET_REFINED/preco_por_periodo/" --recursive --only-show-errors \
    || falhou "falha ao limpar a refined"

  athena_exec "$(sql_arquivo refined_carga.sql)" || falhou "falha no INSERT da refined"
  ok "refined preco_por_periodo  ($(fmt_bytes "$ATHENA_BYTES") escaneados na trusted)"
}

# ============================================================

titulo "Ingestão do Data Lake — grupo $GRUPO  (região $REGIAO)"

if [ -z "$PARTICAO" ]; then
  # ---------------------------------------------------- carga completa
  etapa "1/4 raw — envio do arquivo bruto"
  [ -f "$ARQUIVO_DADOS" ] || falhou "arquivo não encontrado: $ARQUIVO_DADOS"

  # Mesmo nome de objeto a cada execução: reenviar sobrescreve (idempotente).
  aws_ s3 cp "$ARQUIVO_DADOS" "s3://$BUCKET_RAW/$CHAVE_RAW" --only-show-errors \
    || falhou "falha no upload para a raw"
  ok "s3://$BUCKET_RAW/$CHAVE_RAW"

  etapa "2/4 partições encontradas na raw"
  athena_exec "SELECT DISTINCT TRIM(source_city) FROM $TABELA_RAW WHERE TRIM(source_city) <> '' ORDER BY 1" \
    || falhou "falha ao listar cidades na raw"
  mapfile -t CIDADES < <(athena_linhas)
  ok "${#CIDADES[@]} partições: ${CIDADES[*]}"
else
  # ---------------------------------------------------- backfill
  [[ "$PARTICAO" =~ ^[A-Za-z_]+$ ]] || falhou "nome de partição inválido: $PARTICAO"

  etapa "1-2/4 backfill da partição source_city=$PARTICAO (a raw já está carregada)"
  aws_ s3api head-object --bucket "$BUCKET_RAW" --key "$CHAVE_RAW" >/dev/null 2>&1 \
    || falhou "a raw está vazia; rode primeiro a carga completa (sem --particao)"

  ANTES="$(contar_particao "$PARTICAO")"
  info "registros na partição antes do backfill: $ANTES"
  CIDADES=("$PARTICAO")
fi

etapa "3/4 trusted — Parquet particionado por source_city"
for cidade in "${CIDADES[@]}"; do
  [[ "$cidade" =~ ^[A-Za-z_]+$ ]] || falhou "nome de partição inválido vindo da raw: $cidade"
  carregar_particao_trusted "$cidade"
done

etapa "4/4 refined — agregado por class x períodos"
recarregar_refined

# ---------------------------------------------------------- resumo
etapa "Resumo"

if [ -n "$PARTICAO" ]; then
  DEPOIS="$(contar_particao "$PARTICAO")"
  info "partição source_city=$PARTICAO: antes=$ANTES depois=$DEPOIS"
  if [ "$ANTES" = "$DEPOIS" ] || [ "$ANTES" = "0" ]; then
    ok "backfill idempotente (nenhum registro duplicado)"
  else
    aviso "a contagem mudou ($ANTES -> $DEPOIS): a raw foi alterada desde a última carga?"
  fi
fi

athena_exec "SELECT COUNT(*) FROM $TABELA_RAW" || falhou "falha ao contar a raw"
TOTAL_RAW="$(athena_valor)"

athena_exec "SELECT COUNT(*), COUNT(DISTINCT id_oferta) FROM $TABELA_TRUSTED" \
  || falhou "falha ao contar a trusted"
read -r TOTAL_TRUSTED DISTINTOS < <(athena_linhas)

athena_exec "SELECT SUM(qtd_passagens) FROM $TABELA_REFINED" || falhou "falha ao contar a refined"
TOTAL_REFINED="$(athena_valor)"

info "raw:     $TOTAL_RAW linhas"
info "trusted: $TOTAL_TRUSTED linhas, $DISTINTOS id_oferta distintos  (descartadas na limpeza: $((TOTAL_RAW - TOTAL_TRUSTED)))"
info "refined: soma de qtd_passagens = $TOTAL_REFINED"

athena_exec "SELECT source_city, COUNT(*), CAST(MAX(ingerido_em) AS VARCHAR) FROM $TABELA_TRUSTED GROUP BY 1 ORDER BY 1" \
  || falhou "falha ao listar partições"
athena_linhas | while IFS=$'\t' read -r c n t; do
  info "  source_city=$(printf '%-10s' "$c")  $(printf '%6s' "$n") linhas  ingerido_em=$t"
done

[ "$TOTAL_TRUSTED" = "$DISTINTOS" ] || falhou "há id_oferta duplicado na trusted"
[ "$TOTAL_REFINED" = "$TOTAL_TRUSTED" ] || falhou "refined não fecha com a trusted"

ok "ingestão concluída — total escaneado nesta execução: $(fmt_bytes "$ATHENA_TOTAL_BYTES")"
