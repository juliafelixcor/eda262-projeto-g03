data "aws_caller_identity" "atual" {}

# Resolve o ARN "de verdade" de quem roda o Terraform (para sessões de
# role assumida, devolve o ARN da role e não o da sessão STS).
data "aws_iam_session_context" "atual" {
  arn = data.aws_caller_identity.atual.arn
}

locals {
  conta          = data.aws_caller_identity.atual.account_id
  engenheiro_arn = data.aws_iam_session_context.atual.issuer_arn
}

# ------------------------------------------------------------
# Role que o Lake Formation usa para ler/gravar nos buckets registrados.
# Role própria (e não a service-linked) para o destroy não deixar órfão.
# ------------------------------------------------------------

resource "aws_iam_role" "lakeformation_acesso" {
  name        = "${local.prefixo}-lakeformation-acesso"
  description = "Acesso do Lake Formation aos buckets raw/trusted/refined"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lakeformation.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lakeformation_acesso" {
  name = "s3-camadas"
  role = aws_iam_role.lakeformation_acesso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [for b in aws_s3_bucket.camada : "${b.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [for b in aws_s3_bucket.camada : b.arn]
      },
    ]
  })
}

# ------------------------------------------------------------
# Personas consumidoras. O IAM libera Athena/Glue de forma ampla de
# propósito: quem separa as camadas é o Lake Formation.
# ------------------------------------------------------------

resource "aws_iam_role" "persona" {
  for_each = local.personas

  name        = "${local.prefixo}-${each.key}"
  description = each.value

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${local.conta}:root" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "persona_consulta" {
  for_each = local.personas

  name = "consulta-athena"
  role = aws_iam_role.persona[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Athena"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:GetWorkGroup",
        ]
        Resource = aws_athena_workgroup.this.arn
      },
      {
        Sid    = "CatalogoGlue"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase", "glue:GetDatabases",
          "glue:GetTable", "glue:GetTables",
          "glue:GetPartition", "glue:GetPartitions",
        ]
        Resource = "*"
      },
      {
        Sid      = "LakeFormation"
        Effect   = "Allow"
        Action   = ["lakeformation:GetDataAccess"]
        Resource = "*"
      },
      {
        Sid    = "ResultadosAthena"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload",
          "s3:ListBucket", "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.athena_results.arn,
          "${aws_s3_bucket.athena_results.arn}/*",
        ]
      },
    ]
  })
}
