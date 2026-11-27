# ============================================================
# Bootstrap do backend remoto (rodar UMA vez por conta, antes do
# terraform init de parte-2/).
#
# Cria o bucket do state e a tabela de lock que parte-2/backend.tf usa.
# Usa state LOCAL de propósito: o backend remoto ainda não existe quando
# este código roda (problema do ovo e da galinha).
#
#   terraform -chdir=parte-2/bootstrap init
#   terraform -chdir=parte-2/bootstrap apply
#
# Destroy: só DEPOIS do destroy de parte-2/ (senão o state da stack se perde).
#   terraform -chdir=parte-2/bootstrap destroy
# ============================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Mesmas tags obrigatórias da stack principal.
  default_tags {
    tags = {
      turma   = "eda262"
      grupo   = var.grupo
      projeto = "engenharia-de-dados"
    }
  }
}

locals {
  bucket_state = coalesce(var.bucket_state, "eda262-${var.grupo}-terraform-state")
  tabela_lock  = coalesce(var.tabela_lock, "eda262-${var.grupo}-terraform-locks")
}

# ------------------------------------------------------------ state

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_state

  # O bucket é versionado; sem isso o destroy falha com "bucket not empty"
  # por causa das versões antigas do state (erro apontado na Parte 1).
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------ lock

resource "aws_dynamodb_table" "lock" {
  name         = local.tabela_lock
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
