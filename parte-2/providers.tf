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

  # Tags obrigatórias aplicadas a todo recurso que aceita tags.
  default_tags {
    tags = {
      turma   = "eda262"
      grupo   = var.grupo
      projeto = "engenharia-de-dados"
    }
  }
}
