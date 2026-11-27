#!/usr/bin/env bash
# Funções e nomes compartilhados pela ingestão e pelo verifica.sh.
# Uso: source parte-2/scripts/athena.sh

REGIAO="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
GRUPO="${GRUPO:-g03}"

PREFIXO="eda262-${GRUPO}"
PREFIXO_DB="eda262_${GRUPO}"

WORKGROUP="${PREFIXO}-athena"
BUCKET_RAW="${PREFIXO}-lake-raw"
BUCKET_TRUSTED="${PREFIXO}-lake-trusted"
BUCKET_REFINED="${PREFIXO}-lake-refined"
BUCKET_RESULTADOS="${PREFIXO}-athena-results"

DB_RAW="${PREFIXO_DB}_raw"
DB_TRUSTED="${PREFIXO_DB}_trusted"
DB_REFINED="${PREFIXO_DB}_refined"

TABELA_RAW="${DB_RAW}.flights"
TABELA_TRUSTED="${DB_TRUSTED}.flights"
TABELA_REFINED="${DB_REFINED}.preco_por_periodo"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARTE2_DIR="$(cd "$LIB_DIR/.." && pwd)"
RAIZ_DIR="$(cd "$PARTE2_DIR/.." && pwd)"
SQL_DIR="$PARTE2_DIR/sql"

ARQUIVO_DADOS="$RAIZ_DIR/dados/airlines_flights_data.csv.gz"
CHAVE_RAW="flights/airlines_flights_data.csv.gz"

# ------------------------------------------------------------ saída
if [ -t 1 ]; then
  C_OK=$'\e[32m'; C_ERRO=$'\e[31m'; C_AVISO=$'\e[33m'; C_DIM=$'\e[2m'; C_B=$'\e[1m'; C_X=$'\e[0m'
else
  C_OK=""; C_ERRO=""; C_AVISO=""; C_DIM=""; C_B=""; C_X=""
fi

titulo() { printf '%s%s%s\n' "$C_B" "$1" "$C_X"; }
etapa()  { printf '\n%s== %s%s\n' "$C_B" "$1" "$C_X"; }
ok()     { printf '%s  ok%s  %s\n' "$C_OK" "$C_X" "$1"; }
aviso()  { printf '%s  !!%s  %s\n' "$C_AVISO" "$C_X" "$1"; }
erro()   { printf '%sERRO%s  %s\n' "$C_ERRO" "$C_X" "$1" >&2; }
info()   { printf '%s        %s%s\n' "$C_DIM" "$1" "$C_X"; }

# bytes -> texto legível (ex.: 1.84 MB)
fmt_bytes() {
  awk -v b="${1:-0}" 'BEGIN {
    if (b >= 1000000) printf "%.2f MB", b/1000000;
    else if (b >= 1000) printf "%.2f KB", b/1000;
    else printf "%d B", b }'
}

# ------------------------------------------------------------ AWS
# A AWS CLI no Windows devolve \r no fim das linhas; removemos aqui.
aws_() { aws --region "$REGIAO" "$@" | tr -d '\r'; }

# Lê um arquivo SQL de parte-2/sql removendo linhas de comentário.
sql_arquivo() { sed -e '/^[[:space:]]*--/d' "$SQL_DIR/$1"; }

# Teste das regras de limpeza: reaproveita trusted_carga_particao.sql sem o
# INSERT, lendo o lote de sql/testes/limpeza_sujeira_valores.sql no lugar
# da tabela raw. Colunas: aprovadas, ids aprovados, aprovadas normalizadas.
sql_teste_limpeza() {
  local colunas valores carga montado
  colunas='"index", airline, flight, source_city, departure_time, stops, arrival_time, destination_city, "class", duration, days_left, price'
  valores="$(sql_arquivo testes/limpeza_sujeira_valores.sql)"
  carga="$(sql_arquivo trusted_carga_particao.sql | sed -e '/^INSERT INTO/d' -e 's/{{CIDADE}}/Delhi/g')"
  montado="${carga//FROM eda262_g03_raw.flights/FROM ($valores) AS raw($colunas)}"
  # Se a troca da fonte não acontecer, falha em vez de testar a tabela real.
  [ "$montado" != "$carga" ] || return 1
  printf '%s\n' "SELECT
    COUNT(*) AS aprovadas,
    array_join(array_sort(array_agg(CAST(id_oferta AS VARCHAR))), ',') AS ids,
    count_if(airline = 'Vistara' AND flight IN ('UK-1', 'UK-2') AND stops = 'zero') AS normalizadas
FROM (
$montado
) t"
}

# ------------------------------------------------------------ Athena
ATHENA_ID=""
ATHENA_BYTES=0
ATHENA_ERRO=""
ATHENA_TOTAL_BYTES=0

# Executa uma consulta no workgroup do grupo e espera terminar.
# Define ATHENA_ID, ATHENA_BYTES e (em caso de falha) ATHENA_ERRO.
athena_exec() {
  local sql="$1" estado="" bytes="" tentativas=0

  ATHENA_ERRO=""
  ATHENA_BYTES=0

  ATHENA_ID="$(aws_ athena start-query-execution \
      --work-group "$WORKGROUP" \
      --query-string "$sql" \
      --query QueryExecutionId --output text 2>/tmp/athena-erro.txt)"

  if [ -z "$ATHENA_ID" ]; then
    ATHENA_ERRO="$(tr -d '\r' </tmp/athena-erro.txt | grep -v '^[[:space:]]*$' | tail -1)"
    [ -n "$ATHENA_ERRO" ] || ATHENA_ERRO="start-query-execution não devolveu id (sem mensagem)"
    return 1
  fi

  while true; do
    read -r estado bytes < <(aws_ athena get-query-execution \
        --query-execution-id "$ATHENA_ID" \
        --query '[QueryExecution.Status.State, QueryExecution.Statistics.DataScannedInBytes]' \
        --output text 2>/dev/null)

    case "$estado" in
      SUCCEEDED) break ;;
      FAILED|CANCELLED)
        ATHENA_ERRO="$(aws_ athena get-query-execution \
            --query-execution-id "$ATHENA_ID" \
            --query QueryExecution.Status.StateChangeReason --output text)"
        return 1 ;;
      "")
        tentativas=$((tentativas + 1))
        if [ "$tentativas" -ge 5 ]; then
          ATHENA_ERRO="não foi possível consultar o estado da execução $ATHENA_ID"
          return 1
        fi ;;
    esac
    sleep 1
  done

  case "$bytes" in ''|None) bytes=0 ;; esac
  ATHENA_BYTES="$bytes"
  ATHENA_TOTAL_BYTES=$((ATHENA_TOTAL_BYTES + bytes))
}

# Linhas do último resultado (sem cabeçalho), colunas separadas por TAB.
athena_linhas() {
  aws_ athena get-query-results \
    --query-execution-id "$ATHENA_ID" \
    --query 'ResultSet.Rows[1:].Data[*].VarCharValue' \
    --output text
}

# Primeira coluna da primeira linha do último resultado.
athena_valor() { athena_linhas | head -n 1 | cut -f1; }
