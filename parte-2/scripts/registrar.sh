#!/usr/bin/env bash
# ============================================================
# Roda um comando e grava a saída em evidencias/parte-2/logs/<nome>.log
#
#   bash parte-2/scripts/registrar.sh <nome> <comando> [argumentos...]
#
# Exemplos:
#   bash parte-2/scripts/registrar.sh apply   terraform -chdir=parte-2 apply -no-color
#   bash parte-2/scripts/registrar.sh verifica bash verificacao/verifica.sh
#
# O log leva cabeçalho (data, conta, região, commit, comando) e rodapé
# (código de saída e duração). O código de saída do comando é preservado.
# ============================================================

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$RAIZ/evidencias/parte-2/logs"

if [ $# -lt 2 ]; then
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
fi

NOME="$1"; shift
[[ "$NOME" =~ ^[a-z0-9-]+$ ]] || { echo "nome inválido (use minúsculas, números e hífen): $NOME" >&2; exit 1; }

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$NOME.log"

REGIAO="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
CONTA="$(aws --region "$REGIAO" sts get-caller-identity --query Account --output text 2>/dev/null | tr -d '\r')"
COMMIT="$(git -C "$RAIZ" rev-parse HEAD 2>/dev/null || echo desconhecido)"
# Alterações só em evidencias/ não contam como código alterado.
[ -n "$(git -C "$RAIZ" status --porcelain -- . ':(exclude)evidencias' 2>/dev/null)" ] \
  && COMMIT="$COMMIT (com alterações não commitadas)"

{
  echo "# evidência: $NOME"
  echo "# início (UTC): $(date -u '+%Y-%m-%d %H:%M:%S')"
  echo "# conta AWS:    ${CONTA:-?}   região: $REGIAO"
  echo "# commit:       $COMMIT"
  echo "# comando:      $*"
  echo "# ------------------------------------------------------------"
} >"$LOG"

INICIO="$(date +%s)"
"$@" 2>&1 | tee -a "$LOG"
RC="${PIPESTATUS[0]}"
DURACAO=$(( $(date +%s) - INICIO ))

{
  echo "# ------------------------------------------------------------"
  echo "# fim (UTC):    $(date -u '+%Y-%m-%d %H:%M:%S')   duração: ${DURACAO}s   código de saída: $RC"
} >>"$LOG"

# Remove códigos de cor ANSI do arquivo (o terminal continua colorido).
sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g' "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"

echo
echo "log gravado em: evidencias/parte-2/logs/$NOME.log (código de saída $RC)"
exit "$RC"
