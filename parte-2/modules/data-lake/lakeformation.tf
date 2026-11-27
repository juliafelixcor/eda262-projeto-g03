# ------------------------------------------------------------
# Configurações do Lake Formation
#
# - Mantém os admins que já existirem na conta e acrescenta quem roda o
#   Terraform (a conta da disciplina é compartilhada entre grupos).
# - Sem blocos create_*_default_permissions: novas databases/tabelas NÃO
#   recebem grant automático para IAM_ALLOWED_PRINCIPALS, ou seja, o acesso
#   passa a depender só dos grants abaixo.
# ------------------------------------------------------------

data "aws_lakeformation_data_lake_settings" "atual" {}

resource "aws_lakeformation_data_lake_settings" "this" {
  admins = distinct(concat(
    tolist(data.aws_lakeformation_data_lake_settings.atual.admins),
    [local.engenheiro_arn],
  ))
}

# ------------------------------------------------------------
# Registro dos buckets das camadas no Lake Formation
# ------------------------------------------------------------

resource "aws_lakeformation_resource" "camada" {
  for_each = local.camadas

  arn      = aws_s3_bucket.camada[each.key].arn
  role_arn = aws_iam_role.lakeformation_acesso.arn

  depends_on = [
    aws_lakeformation_data_lake_settings.this,
    aws_iam_role_policy.lakeformation_acesso,
    # registra só depois que as tabelas existem
    aws_glue_catalog_table.raw_flights,
    aws_glue_catalog_table.trusted_flights,
    aws_glue_catalog_table.refined_preco_por_periodo,
  ]
}

# ------------------------------------------------------------
# Engenheiro (quem roda Terraform + ingestão): acesso total às 3 camadas
# ------------------------------------------------------------

# Nas databases o engenheiro não precisa de grant declarado: quem cria a
# database já recebe ALL do Lake Formation. Declarar o grant aqui faria o
# destroy revogá-lo antes de apagar as databases (o grant depende delas),
# e o DeleteDatabase falharia por falta de DROP.

resource "aws_lakeformation_permissions" "engenheiro_tabelas" {
  for_each = local.camadas

  principal   = local.engenheiro_arn
  permissions = ["ALTER", "DELETE", "DESCRIBE", "DROP", "INSERT", "SELECT"]

  table {
    database_name = aws_glue_catalog_database.camada[each.key].name
    wildcard      = true
  }

  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "engenheiro_local" {
  for_each = local.camadas

  principal   = local.engenheiro_arn
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = aws_lakeformation_resource.camada[each.key].arn
  }

  depends_on = [aws_lakeformation_data_lake_settings.this]
}

# ------------------------------------------------------------
# Personas: somente leitura, por camada (ver locals.leitores_por_camada)
#   raw     -> ninguém além do engenheiro
#   trusted -> cientista
#   refined -> cientista, analista
# ------------------------------------------------------------

resource "aws_lakeformation_permissions" "leitor_database" {
  for_each = local.grants_leitura

  principal   = aws_iam_role.persona[each.value.persona].arn
  permissions = ["DESCRIBE"]

  database {
    name = aws_glue_catalog_database.camada[each.value.camada].name
  }

  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "leitor_tabelas" {
  for_each = local.grants_leitura

  principal   = aws_iam_role.persona[each.value.persona].arn
  permissions = ["DESCRIBE", "SELECT"]

  table {
    database_name = aws_glue_catalog_database.camada[each.value.camada].name
    wildcard      = true
  }

  depends_on = [
    aws_lakeformation_data_lake_settings.this,
    aws_lakeformation_resource.camada,
  ]
}
