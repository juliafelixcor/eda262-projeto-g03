# ------------------------------------------------------------
# Buckets das camadas raw / trusted / refined
# ------------------------------------------------------------

resource "aws_s3_bucket" "camada" {
  for_each = local.bucket_camada

  bucket = each.value

  # Os objetos são gravados pela ingestão (fora do state); sem isso o
  # destroy falharia com bucket não vazio e deixaria recurso órfão.
  force_destroy = true

  tags = {
    camada = each.key
  }
}

resource "aws_s3_bucket_public_access_block" "camada" {
  for_each = local.bucket_camada

  bucket                  = aws_s3_bucket.camada[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versionamento:
# - raw: guarda o arquivo como recebido; versionar permite auditar reenvios.
# - trusted: herdado da Parte 1 (o bucket é o mesmo) e mantido; permite
#   recuperar uma partição sobrescrita por engano.
# Versões antigas expiram em 7 dias para não acumular custo a cada backfill.
locals {
  buckets_versionados = toset(["raw", "trusted"])
}

resource "aws_s3_bucket_versioning" "camada" {
  for_each = local.buckets_versionados

  bucket = aws_s3_bucket.camada[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "camada" {
  for_each = local.buckets_versionados

  bucket = aws_s3_bucket.camada[each.key].id

  rule {
    id     = "expira-versoes-antigas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.camada]
}

# ------------------------------------------------------------
# Bucket dedicado aos resultados do Athena
# (na Parte 1 os resultados no mesmo prefixo dos dados inflaram o COUNT)
# ------------------------------------------------------------

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${local.prefixo}-athena-results"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "expira-resultados"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}
