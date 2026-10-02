resource "aws_s3_bucket" "trusted" {
  bucket = "eda262-g03-lake-trusted"

  tags = {
    turma   = "eda262"
    grupo   = "g03"
    projeto = "engenharia-de-dados"
  }
}

resource "aws_s3_bucket_versioning" "trusted" {
  bucket = aws_s3_bucket.trusted.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_glue_catalog_database" "flights" {
  name = "eda262_g03_flights"

  tags = {
    turma   = "eda262"
    grupo   = "g03"
    projeto = "engenharia-de-dados"
  }
}