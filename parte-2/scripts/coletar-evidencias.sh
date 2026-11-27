#!/usr/bin/env bash
# ============================================================
# Roda as medições citadas no DECISOES.md e grava os resultados em
# evidencias/parte-2/medicoes/.
#
#   bash parte-2/scripts/coletar-evidencias.sh               medições
#   bash parte-2/scripts/coletar-evidencias.sh --parte1-csv  + reprodução
#                                         do custo do CSV da Parte 1
#
# Pré-requisitos: terraform apply + carga completa (ingestao.sh).
#
# Saída em evidencias/parte-2/medicoes/:
#   contexto.txt       data, conta, região, workgroup, commit do código
#   resumo.csv         uma linha por medição: QueryExecutionId, bytes
#                      escaneados, tempo do motor, custo cobrado
#   <medicao>.csv      resultado da consulta, baixado do Athena
#   tamanhos-s3.txt    tamanho em disco de cada camada (aws s3 ls)
#
# O SQL de cada medição está em parte-2/sql/medicoes/ (e, para as consultas
# de negócio, em parte-2/sql/).
# ============================================================

set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/athena.sh"

PARTE1_CSV=0
case "${1:-}" in
  --parte1-csv) PARTE1_CSV=1 ;;
  "") ;;
  -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) erro "argumento desconhecido: $1"; exit 1 ;;
esac

SAIDA="$RAIZ_DIR/evidencias/parte-2/medicoes"
mkdir -p "$SAIDA"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# medição | arquivo SQL (relativo a parte-2/sql)
MEDICOES=(
  "01_contagem_camadas|medicoes/01_contagem_camadas.sql"
  "02_trusted_por_particao|medicoes/02_trusted_por_particao.sql"
  "03_raw_rejeicao_por_regra|medicoes/03_raw_rejeicao_por_regra.sql"
  "04_raw_duplicatas_exatas|medicoes/04_raw_duplicatas_exatas.sql"
  "05_chave_natural_colisoes|medicoes/05_chave_natural_colisoes.sql"
  "06_distribuicao_departure_time|medicoes/06_distribuicao_departure_time.sql"
  "07_refined_linhas_por_classe|medicoes/07_refined_linhas_por_classe.sql"
  "08_pruning_sem_filtro|medicoes/08_pruning_sem_filtro.sql"
  "09_pruning_delhi|medicoes/09_pruning_delhi.sql"
  "10_negocio_refined|consulta_negocio_refined.sql"
  "11_negocio_trusted|consulta_negocio_trusted.sql"
  "12_negocio_refined_so_economy|consulta_negocio_por_classe.sql"
  "13_razao_por_classe|medicoes/13_razao_por_classe.sql"
  "14_count_trusted_metadados|medicoes/14_count_trusted_metadados.sql"
  "15_voos_e_rotas|medicoes/15_voos_e_rotas.sql"
)

# Custo cobrado pelo Athena: US$ 5,00 por TB, arredondado para cima ao MB,
# mínimo de 10 MB por consulta (MB e TB decimais, como no DECISOES.md).
custo_usd() {
  # LC_ALL=C para o awk usar ponto decimal mesmo em locale pt_BR
  LC_ALL=C awk -v b="${1:-0}" 'BEGIN {
    mb = int((b + 999999) / 1000000); if (mb < 10) mb = 10;
    printf "%.6f", mb * 5 / 1000000 }'
}

FALHAS=0

# Roda uma consulta e registra: resultado (.csv) + linha no resumo.
medir() {
  local nome="$1" sql_rel="$2" sql="$3" estado bytes ms saida
  if ! athena_exec "$sql"; then
    aviso "$nome: FALHOU — $ATHENA_ERRO"
    printf '%s,%s,FAILED,,,,%s,\n' "$nome" "${ATHENA_ID:-}" "$sql_rel" >>"$SAIDA/resumo.csv"
    FALHAS=$((FALHAS + 1))
    return 1
  fi

  read -r estado bytes ms saida < <(aws_ athena get-query-execution \
      --query-execution-id "$ATHENA_ID" \
      --query '[QueryExecution.Status.State, QueryExecution.Statistics.DataScannedInBytes, QueryExecution.Statistics.EngineExecutionTimeInMillis, QueryExecution.ResultConfiguration.OutputLocation]' \
      --output text)
  case "$bytes" in ''|None) bytes=0 ;; esac
  case "$ms" in ''|None) ms="" ;; esac

  # O CSV de resultado que o próprio Athena gravou (com cabeçalho).
  if ! aws_ s3 cp "$saida" "$SAIDA/$nome.csv" --only-show-errors; then
    aviso "$nome: não foi possível baixar o resultado de $saida"
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$nome" "$ATHENA_ID" "$estado" "$bytes" "$ms" "$(custo_usd "$bytes")" \
    "parte-2/sql/$sql_rel" "evidencias/parte-2/medicoes/$nome.csv" >>"$SAIDA/resumo.csv"
  ok "$(printf '%-32s %12s B  %s' "$nome" "$bytes" "$(fmt_bytes "$bytes")")"
}

# ============================================================

titulo "Coleta de evidências — grupo $GRUPO (região $REGIAO)"

CONTA="$(aws_ sts get-caller-identity --query Account --output text 2>/dev/null)"
[ -n "$CONTA" ] || { erro "sem credenciais AWS válidas"; exit 2; }

COMMIT="$(git -C "$RAIZ_DIR" rev-parse HEAD 2>/dev/null || echo desconhecido)"
if [ -n "$(git -C "$RAIZ_DIR" status --porcelain -- parte-2 2>/dev/null)" ]; then
  ALTERADO="sim — o código em parte-2/ tem alterações não commitadas"
  aviso "parte-2/ tem alterações não commitadas: o contexto.txt vai registrar isso"
else
  ALTERADO="não"
fi

{
  echo "Coleta de evidências — Parte 2"
  echo "data (UTC):        $(date -u '+%Y-%m-%d %H:%M:%S')"
  echo "conta AWS:         $CONTA"
  echo "região:            $REGIAO"
  echo "workgroup Athena:  $WORKGROUP"
  echo "commit do código:  $COMMIT"
  echo "código alterado:   $ALTERADO"
  echo "workspace:         $(terraform -chdir="$PARTE2_DIR" workspace show 2>/dev/null || echo '?')"
} >"$SAIDA/contexto.txt"

echo "medicao,query_execution_id,estado,bytes_escaneados,tempo_motor_ms,custo_cobrado_usd,arquivo_sql,arquivo_resultado" \
  >"$SAIDA/resumo.csv"

etapa "Medições no Athena"
for item in "${MEDICOES[@]}"; do
  nome="${item%%|*}"
  sql_rel="${item#*|}"
  [ -f "$SQL_DIR/$sql_rel" ] || { aviso "$nome: arquivo ausente $SQL_DIR/$sql_rel"; FALHAS=$((FALHAS + 1)); continue; }
  medir "$nome" "$sql_rel" "$(sql_arquivo "$sql_rel")" || true
done

# ------------------------------------------------------------
# Reprodução do CSV da Parte 1 (opcional)
# Sobe o CSV sem compressão num prefixo temporário da raw, cria uma tabela
# temporária com o schema da Parte 1, mede a consulta de negócio e remove
# tabela e arquivos ao final (inclusive se algo falhar no meio).
# ------------------------------------------------------------
if [ "$PARTE1_CSV" = "1" ]; then
  etapa "Reprodução do custo da Parte 1 (CSV sem compressão)"
  PREFIXO_TMP="s3://$BUCKET_RAW/medicao_parte1_csv/"

  limpar_parte1() {
    athena_exec "DROP TABLE IF EXISTS $DB_RAW.medicao_parte1_csv" \
      || aviso "não removeu a tabela temporária: $ATHENA_ERRO"
    aws_ s3 rm "$PREFIXO_TMP" --recursive --only-show-errors \
      || aviso "não removeu $PREFIXO_TMP"
  }
  trap 'limpar_parte1; rm -rf "$TMP"' EXIT

  gunzip -c "$ARQUIVO_DADOS" >"$TMP/airlines_flights_data.csv"
  TAM_CSV="$(wc -c <"$TMP/airlines_flights_data.csv" | tr -d ' ')"
  info "CSV sem compressão: $TAM_CSV bytes"
  echo "tamanho do CSV sem compressão (bytes): $TAM_CSV" >>"$SAIDA/contexto.txt"

  if aws_ s3 cp "$TMP/airlines_flights_data.csv" "${PREFIXO_TMP}airlines_flights_data.csv" --only-show-errors \
     && athena_exec "$(sql_arquivo medicoes/90_parte1_csv_ddl.sql | sed "s|{{LOCAL}}|$PREFIXO_TMP|")"; then
    medir "90_parte1_csv" "medicoes/90_parte1_csv_consulta.sql" "$(sql_arquivo medicoes/90_parte1_csv_consulta.sql)" || true
  else
    aviso "falha ao preparar a tabela temporária: $ATHENA_ERRO"
    FALHAS=$((FALHAS + 1))
  fi
  limpar_parte1
  trap 'rm -rf "$TMP"' EXIT
fi

# ------------------------------------------------------------
# Tamanho em disco das camadas
# ------------------------------------------------------------
etapa "Tamanho das camadas no S3"
{
  echo "# aws s3 ls --recursive --summarize — $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
  for alvo in "$BUCKET_RAW/flights/" "$BUCKET_TRUSTED/flights/" "$BUCKET_REFINED/preco_por_periodo/"; do
    echo
    echo "## s3://$alvo"
    aws_ s3 ls "s3://$alvo" --recursive --summarize
  done
} >"$SAIDA/tamanhos-s3.txt" 2>&1
grep -E '^## |Total Size' "$SAIDA/tamanhos-s3.txt" | paste - - | while IFS=$'\t' read -r alvo total; do
  info "$alvo  ${total#*: } bytes"
done

# ------------------------------------------------------------
etapa "Resumo"
info "arquivos em evidencias/parte-2/medicoes/ ($(ls "$SAIDA" | wc -l | tr -d ' ') arquivos)"
if [ "$FALHAS" -gt 0 ]; then
  erro "$FALHAS medição(ões) falharam — veja resumo.csv"
  exit 1
fi
ok "todas as medições registradas — total escaneado: $(fmt_bytes "$ATHENA_TOTAL_BYTES")"
