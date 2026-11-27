#!/usr/bin/env bash
# ============================================================
# Verificação da Parte 2 (AV2) — Grupo 03
#
#   bash verificacao/verifica.sh                 todos os critérios
#   bash verificacao/verifica.sh --sem-backfill  pula o teste de backfill
#   bash verificacao/verifica.sh --pos-destroy   confere que nada sobrou
#
# Pré-requisitos: terraform init + workspace selecionado em parte-2/,
# terraform apply e uma carga completa (parte-2/scripts/ingestao.sh).
# A verificação da Parte 1 está em verificacao/verifica-parte-1.sh.
# ============================================================

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFDIR="${TFDIR:-$RAIZ/parte-2}"
DECISOES="${DECISOES:-$RAIZ/DECISOES.md}"

# shellcheck source=../parte-2/scripts/athena.sh
source "$TFDIR/scripts/athena.sh"

# Meta de custo declarada no DECISOES.md (seção "Meta de custo"):
# a consulta de negócio escaneia no máximo 1 MiB.
META_BYTES="${META_BYTES:-1048576}"
BYTES_PARTE1=24946485
PARTICAO_BACKFILL="${PARTICAO_BACKFILL:-Delhi}"

MODO="completo"
case "${1:-}" in
  --pos-destroy)  MODO="pos-destroy" ;;
  --sem-backfill) MODO="sem-backfill" ;;
  "") ;;
  *) echo "uso: $0 [--sem-backfill | --pos-destroy]"; exit 1 ;;
esac

notas=0
total=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

linha() { printf '%s\n' "----------------------------------------------------------------"; }
pass()  { notas=$((notas + $2)); total=$((total + $2)); printf "${C_OK}PASSA${C_X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
fail()  { total=$((total + $2)); printf "${C_ERRO}FALHA${C_X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }

tfout() { terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null; }

CONTA="$(aws_ sts get-caller-identity --query Account --output text 2>/dev/null)"
if [ -z "$CONTA" ]; then
  echo "${C_ERRO}Sem credenciais AWS válidas (aws sts get-caller-identity falhou).${C_X}"
  exit 2
fi

# ============================================================
# Pós-destroy
# ============================================================

if [ "$MODO" = "pos-destroy" ]; then
  titulo "Pós-destroy — nada do grupo $GRUPO pode sobrar (conta $CONTA)"
  linha

  sobras=""

  # Logo após o destroy, o head-bucket pode responder por alguns segundos
  # que um bucket já excluído ainda existe. Só conta como órfão se continuar
  # existindo depois de ~60 s.
  bucket_persiste() {
    local tentativa
    for tentativa in 1 2 3 4 5 6 7; do
      aws_ s3api head-bucket --bucket "$1" >/dev/null 2>&1 || return 1
      [ "$tentativa" -lt 7 ] && { info "$1 ainda responde; aguardando a propagação da exclusão ($tentativa/6)"; sleep 10; }
    done
    return 0
  }

  for b in "$BUCKET_RAW" "$BUCKET_TRUSTED" "$BUCKET_REFINED" "$BUCKET_RESULTADOS"; do
    bucket_persiste "$b" && sobras="$sobras bucket:$b"
  done

  for d in "$DB_RAW" "$DB_TRUSTED" "$DB_REFINED"; do
    aws_ glue get-database --name "$d" >/dev/null 2>&1 && sobras="$sobras glue:$d"
  done

  aws_ athena get-work-group --work-group "$WORKGROUP" >/dev/null 2>&1 && sobras="$sobras workgroup:$WORKGROUP"

  for r in lakeformation-acesso analista cientista; do
    aws_ iam get-role --role-name "$PREFIXO-$r" >/dev/null 2>&1 && sobras="$sobras role:$PREFIXO-$r"
  done

  registrados="$(aws_ lakeformation list-resources --query 'ResourceInfoList[].ResourceArn' --output text 2>/dev/null)"
  for b in "$BUCKET_RAW" "$BUCKET_TRUSTED" "$BUCKET_REFINED"; do
    grep -q "arn:aws:s3:::$b\b" <<<"$registrados" && sobras="$sobras lakeformation:$b"
  done

  if [ -z "$sobras" ]; then
    pass "D" 100 "destroy limpo: nenhum bucket, database, workgroup, role ou registro do Lake Formation restante."
  else
    fail "D" 100 "recursos órfãos:$sobras"
  fi

  linha
  titulo "Resultado pós-destroy: $notas / $total"
  exit 0
fi

titulo "Projeto Engenharia de Dados — Parte 2 — Grupo $GRUPO (conta $CONTA, $REGIAO)"
linha

# ============================================================
# Critério 0 — estrutura (pré-requisito)
# ============================================================

titulo "Critério 0 — módulo + backend remoto + workspace"

grep -qE '^\s*module\s+"' "$TFDIR"/*.tf 2>/dev/null   || { fail "0" 0 "bloco module ausente em $TFDIR"; exit 2; }
[ -d "$TFDIR/modules" ]                                || { fail "0" 0 "pasta modules/ ausente"; exit 2; }
grep -qE 'backend\s+"s3"' "$TFDIR"/*.tf 2>/dev/null    || { fail "0" 0 "backend S3 ausente"; exit 2; }
grep -q 'dynamodb_table' "$TFDIR"/backend.tf 2>/dev/null || { fail "0" 0 "lock DynamoDB ausente no backend"; exit 2; }

WS="$(terraform -chdir="$TFDIR" workspace show 2>/dev/null)"
printf "${C_OK}OK${C_X}     [0] módulo, backend S3 + DynamoDB; workspace atual: %s\n" "${WS:-?}"
linha

# ============================================================
# Critério 1 — plan limpo
# ============================================================

titulo "Critério 1 — terraform plan limpo"

terraform -chdir="$TFDIR" plan -detailed-exitcode -input=false -no-color >"$TMP/plan.txt" 2>&1
rc=$?
if [ "$rc" = "0" ]; then
  pass "1" 10 "No changes — infraestrutura igual ao código."
elif [ "$rc" = "2" ]; then
  fail "1" 10 "o plan quer alterar recursos:"
  grep -E '^\s+# .* (will|must) be' "$TMP/plan.txt" | head -8
else
  fail "1" 10 "erro no terraform plan:"
  tail -6 "$TMP/plan.txt"
fi
linha

# ============================================================
# Critério 2 — camadas no S3 + tags obrigatórias
# ============================================================

titulo "Critério 2 — buckets raw / trusted / refined e tags"

faltando=""
sem_tag=""
for b in "$BUCKET_RAW" "$BUCKET_TRUSTED" "$BUCKET_REFINED" "$BUCKET_RESULTADOS"; do
  if ! aws_ s3api head-bucket --bucket "$b" >/dev/null 2>&1; then
    faltando="$faltando $b"
    continue
  fi
  tags="$(aws_ s3api get-bucket-tagging --bucket "$b" \
          --query 'TagSet[].[Key,Value]' --output text 2>/dev/null)"
  for esperado in "turma	eda262" "grupo	$GRUPO" "projeto	engenharia-de-dados"; do
    grep -qx "$esperado" <<<"$tags" || sem_tag="$sem_tag $b(${esperado%%	*})"
  done
done

[ -z "$faltando" ] && pass "2a" 5 "4 buckets existem (3 camadas + resultados do Athena)." \
                   || fail "2a" 5 "buckets ausentes:$faltando"
[ -z "$sem_tag" ]  && pass "2b" 5 "tags turma/grupo/projeto presentes em todos." \
                   || fail "2b" 5 "tags ausentes:$sem_tag"
linha

# ============================================================
# Critério 3 — catálogo: 3 camadas, Parquet particionado, sem crawler
# ============================================================

titulo "Critério 3 — Glue Data Catalog"

serde() {
  aws_ glue get-table --database-name "$1" --name "$2" \
    --query 'Table.StorageDescriptor.SerdeInfo.SerializationLibrary' --output text 2>/dev/null
}
particao() {
  aws_ glue get-table --database-name "$1" --name "$2" \
    --query 'Table.PartitionKeys[0].Name' --output text 2>/dev/null
}

s_raw="$(serde "$DB_RAW" flights)"
s_tru="$(serde "$DB_TRUSTED" flights)";            p_tru="$(particao "$DB_TRUSTED" flights)"
s_ref="$(serde "$DB_REFINED" preco_por_periodo)";  p_ref="$(particao "$DB_REFINED" preco_por_periodo)"

if [ -n "$s_raw" ] && [ -n "$s_tru" ] && [ -n "$s_ref" ]; then
  pass "3a" 5 "3 databases/tabelas: $TABELA_RAW, $TABELA_TRUSTED, $TABELA_REFINED."
else
  fail "3a" 5 "tabelas ausentes (raw='$s_raw' trusted='$s_tru' refined='$s_ref')."
fi

if [[ "$s_tru" == *Parquet* && "$s_ref" == *Parquet* && "$p_tru" == "source_city" && "$p_ref" == "class" ]]; then
  pass "3b" 5 "trusted e refined em Parquet, particionadas por source_city / class."
else
  fail "3b" 5 "formato/partição inesperados (trusted: $s_tru/$p_tru, refined: $s_ref/$p_ref)."
fi

crawlers="$(aws_ glue list-crawlers --output text 2>/dev/null | grep -iE "eda262[-_]$GRUPO" || true)"
[ -z "$crawlers" ] && pass "3c" 5 "schemas declarados no Terraform (nenhum Crawler do grupo)." \
                   || fail "3c" 5 "Crawler encontrado: $crawlers"
linha

# ============================================================
# Critério 4 — Lake Formation: permissão por camada
# ============================================================

titulo "Critério 4 — Lake Formation"

registrados="$(aws_ lakeformation list-resources --query 'ResourceInfoList[].ResourceArn' --output text 2>/dev/null)"
nao_reg=""
for b in "$BUCKET_RAW" "$BUCKET_TRUSTED" "$BUCKET_REFINED"; do
  grep -q "arn:aws:s3:::$b\b" <<<"$registrados" || nao_reg="$nao_reg $b"
done
[ -z "$nao_reg" ] && pass "4a" 5 "3 buckets das camadas registrados no Lake Formation." \
                  || fail "4a" 5 "não registrados:$nao_reg"

ROLE_ANALISTA="$(tfout role_analista_arn)";   ROLE_ANALISTA="${ROLE_ANALISTA:-arn:aws:iam::$CONTA:role/$PREFIXO-analista}"
ROLE_CIENTISTA="$(tfout role_cientista_arn)"; ROLE_CIENTISTA="${ROLE_CIENTISTA:-arn:aws:iam::$CONTA:role/$PREFIXO-cientista}"

# Executa uma consulta assumindo a role da persona.
# Retorno: 0 = consulta OK, 1 = negada por permissão, 2 = outro erro.
como_persona() {
  local role="$1" sql="$2" creds ak sk st
  : >"$TMP/persona-erro.txt"
  creds="$(aws_ sts assume-role --role-arn "$role" --role-session-name "verifica-$GRUPO" \
           --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text 2>"$TMP/assume.txt")"
  if [ -z "$creds" ]; then
    tr -d '\r' <"$TMP/assume.txt" | grep -v '^[[:space:]]*$' | tail -1 >"$TMP/persona-erro.txt"
    return 2
  fi
  read -r ak sk st <<<"$creds"
  (
    export AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_SESSION_TOKEN="$st"
    unset AWS_PROFILE
    if athena_exec "$sql"; then exit 0; fi
    printf '%s\n' "$ATHENA_ERRO" >"$TMP/persona-erro.txt"
    grep -qiE 'permission|denied|not authorized|insufficient' <<<"$ATHENA_ERRO" && exit 1
    exit 2
  )
}

esperado() {  # persona role tabela esperado(permitido|negado)
  local nome="$1" role="$2" tabela="$3" quer="$4" rc obtido tentativa
  # Erro que não é de permissão (ex.: limitação de taxa) é tentado de novo.
  for tentativa in 1 2 3; do
    como_persona "$role" "SELECT COUNT(*) FROM $tabela"
    rc=$?
    [ "$rc" != "2" ] && break
    sleep 3
  done
  case "$rc" in 0) obtido="permitido" ;; 1) obtido="negado" ;; *) obtido="erro" ;; esac
  if [ "$obtido" = "$quer" ]; then
    printf "        %-9s -> %-36s %s ${C_OK}(ok)${C_X}\n" "$nome" "$tabela" "$obtido"
    return 0
  fi
  printf "        %-9s -> %-36s %s ${C_ERRO}(esperado: %s)${C_X}\n" "$nome" "$tabela" "$obtido" "$quer"
  [ -s "$TMP/persona-erro.txt" ] && info "$(head -c 300 "$TMP/persona-erro.txt")"
  return 1
}

matriz_ok=1
esperado analista  "$ROLE_ANALISTA"  "$TABELA_REFINED" permitido || matriz_ok=0
esperado analista  "$ROLE_ANALISTA"  "$TABELA_TRUSTED" negado    || matriz_ok=0
esperado analista  "$ROLE_ANALISTA"  "$TABELA_RAW"     negado    || matriz_ok=0
esperado cientista "$ROLE_CIENTISTA" "$TABELA_REFINED" permitido || matriz_ok=0
esperado cientista "$ROLE_CIENTISTA" "$TABELA_TRUSTED" permitido || matriz_ok=0
esperado cientista "$ROLE_CIENTISTA" "$TABELA_RAW"     negado    || matriz_ok=0

[ "$matriz_ok" = "1" ] && pass "4b" 10 "acesso por camada aplicado pelo Lake Formation (consultas reais com cada persona)." \
                       || fail "4b" 10 "a matriz de acesso por camada não bate com o esperado."
linha

# ============================================================
# Critério 5 — dados nas camadas
# ============================================================

titulo "Critério 5 — dados carregados e consistentes"

if athena_exec "SELECT COUNT(*), COUNT(DISTINCT id_oferta), COUNT(DISTINCT source_city) FROM $TABELA_TRUSTED"; then
  read -r T_TOTAL T_DIST T_PART < <(athena_linhas)
else
  T_TOTAL=0; T_DIST=0; T_PART=0
  info "Athena: $ATHENA_ERRO"
fi
athena_exec "SELECT SUM(qtd_passagens) FROM $TABELA_REFINED" && R_TOTAL="$(athena_valor)" || R_TOTAL=0
athena_exec "SELECT COUNT(*) FROM $TABELA_RAW" && RAW_TOTAL="$(athena_valor)" || RAW_TOTAL=0

info "raw=$RAW_TOTAL  trusted=$T_TOTAL (id distintos=$T_DIST, partições=$T_PART)  refined(soma)=$R_TOTAL"

if [ "${T_TOTAL:-0}" -gt 0 ] && [ "$T_TOTAL" = "$T_DIST" ] && [ "$T_TOTAL" = "$R_TOTAL" ] && [ "${T_PART:-0}" -ge 2 ]; then
  pass "5a" 5 "trusted sem duplicatas, $T_PART partições, refined fecha com a trusted."
else
  fail "5a" 5 "camadas vazias ou inconsistentes (rodou parte-2/scripts/ingestao.sh?)."
fi

# 5b — como o dataset de origem não tem sujeira, as regras de limpeza são
# testadas com o lote de parte-2/sql/testes/limpeza_sujeira_valores.sql:
# das 14 linhas, só os ids 1 e 2 devem passar, já normalizados.
if SQL_LIMPEZA="$(sql_teste_limpeza)" && athena_exec "$SQL_LIMPEZA"; then
  IFS=$'\t' read -r L_APROV L_IDS L_NORM < <(athena_linhas)
  info "lote sujo: 14 linhas -> $L_APROV aprovadas (ids: $L_IDS), normalizadas: $L_NORM | QueryExecutionId: $ATHENA_ID"
else
  L_APROV=""; L_IDS=""; L_NORM=""
  info "Athena: ${ATHENA_ERRO:-não foi possível montar o SQL do teste}"
fi
if [ "$L_APROV" = "2" ] && [ "$L_IDS" = "1,2" ] && [ "$L_NORM" = "2" ]; then
  pass "5b" 5 "regras de limpeza: 12 de 14 linhas sujas barradas (duplicata, tipos, faixas, domínios), 2 aprovadas e normalizadas."
else
  fail "5b" 5 "regras de limpeza não se comportaram como esperado (esperado: 2 aprovadas, ids 1,2)."
fi
linha

# ============================================================
# Critério 6 — ingestão idempotente + backfill de uma partição
# ============================================================

titulo "Critério 6 — idempotência e backfill (source_city=$PARTICAO_BACKFILL)"

if [ "$MODO" = "sem-backfill" ]; then
  fail "6" 15 "não executado (--sem-backfill)."
else
  carimbo() {
    athena_exec "SELECT CAST(MAX(ingerido_em) AS VARCHAR) FROM $TABELA_TRUSTED WHERE source_city = '$PARTICAO_BACKFILL'" \
      && athena_valor
  }
  antes_ts="$(carimbo)"

  info "rodando: bash parte-2/scripts/ingestao.sh --particao $PARTICAO_BACKFILL (log em $TMP/backfill.log)"
  bash "$TFDIR/scripts/ingestao.sh" --particao "$PARTICAO_BACKFILL" >"$TMP/backfill.log" 2>&1
  rc=$?

  depois_ts="$(carimbo)"
  if athena_exec "SELECT COUNT(*), COUNT(DISTINCT id_oferta) FROM $TABELA_TRUSTED"; then
    read -r D_TOTAL D_DIST < <(athena_linhas)
  else
    D_TOTAL=-1; D_DIST=-2
  fi

  info "total antes=$T_TOTAL depois=$D_TOTAL | ingerido_em da partição: $antes_ts -> $depois_ts"

  if [ "$rc" = "0" ] && [ "$D_TOTAL" = "$T_TOTAL" ] && [ "$D_TOTAL" = "$D_DIST" ] && [ "$antes_ts" != "$depois_ts" ]; then
    pass "6" 15 "partição reprocessada sem duplicar registros."
  else
    fail "6" 15 "backfill falhou ou alterou a contagem."
    tail -5 "$TMP/backfill.log"
  fi
fi
linha

# ============================================================
# Critério 7 — meta de custo por consulta
# ============================================================

titulo "Critério 7 — meta de custo da consulta de negócio (≤ $(fmt_bytes "$META_BYTES"))"

if athena_exec "$(sql_arquivo consulta_negocio_refined.sql)"; then
  B_REF="$ATHENA_BYTES"; ID_REF="$ATHENA_ID"
  athena_linhas | sort >"$TMP/ref.txt"
else
  B_REF=-1; info "Athena: $ATHENA_ERRO"
fi

if athena_exec "$(sql_arquivo consulta_negocio_trusted.sql)"; then
  B_TRU="$ATHENA_BYTES"
  athena_linhas | sort >"$TMP/tru.txt"
else
  B_TRU=-1; info "Athena: $ATHENA_ERRO"
fi

info "refined: $(fmt_bytes "$B_REF")  |  trusted (Parquet): $(fmt_bytes "$B_TRU")  |  Parte 1 (CSV): $(fmt_bytes "$BYTES_PARTE1")"
[ "$B_REF" -ge 0 ] 2>/dev/null && info "QueryExecutionId (refined): $ID_REF"

# As duas camadas precisam dar a mesma resposta (tolerância de 0,01 na média).
iguais=0
if [ -s "$TMP/ref.txt" ] && [ -s "$TMP/tru.txt" ]; then
  if paste "$TMP/ref.txt" "$TMP/tru.txt" | awk -F'\t' '
      { if ($1 != $5 || $2 != $6 || $3 != $7) bad = 1
        d = $4 - $8; if (d < 0) d = -d; if (d > 0.01) bad = 1 }
      END { exit bad }'; then
    iguais=1
  fi
fi

if [ "$B_REF" -ge 0 ] && [ "$B_REF" -le "$META_BYTES" ] && [ "$iguais" = "1" ]; then
  pass "7" 15 "meta cumprida ($(fmt_bytes "$B_REF") ≤ $(fmt_bytes "$META_BYTES")) e refined = trusted."
else
  fail "7" 15 "meta não cumprida ou refined diverge da trusted (iguais=$iguais)."
fi
linha

# ============================================================
# Critério 8 — DECISOES.md fechado
# ============================================================

titulo "Critério 8 — DECISOES.md"

faltam=""
for termo in "Grão" "Chave" "Partição" "Formato" "Custo" "Meta de custo" "Idempot" "Lake Formation"; do
  grep -qi "$termo" "$DECISOES" 2>/dev/null || faltam="$faltam '$termo'"
done
[ -z "$faltam" ] && pass "8" 10 "decisões de grão, chaves, partição, formato, custo, idempotência e acesso documentadas." \
                 || fail "8" 10 "seções ausentes no DECISOES.md:$faltam"
linha

titulo "Resultado automático: $notas / $total"
info "Depois do terraform destroy: bash verificacao/verifica.sh --pos-destroy"
