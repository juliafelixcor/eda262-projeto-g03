resource "aws_athena_workgroup" "this" {
  name = "${local.prefixo}-athena"

  # Remove o histórico/consultas salvas junto no destroy (evita órfão).
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    # Trava de custo: nenhuma consulta do grupo escaneia mais de 100 MB.
    bytes_scanned_cutoff_per_query = 104857600

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

# Consultas da pergunta de negócio versionadas no IaC.
resource "aws_athena_named_query" "negocio_refined" {
  name        = "${local.prefixo}-negocio-refined"
  description = "Preco medio por periodo de partida/chegada (camada refined)"
  workgroup   = aws_athena_workgroup.this.id
  database    = aws_glue_catalog_database.camada["refined"].name
  query       = file("${path.module}/../../sql/consulta_negocio_refined.sql")
}

resource "aws_athena_named_query" "negocio_trusted" {
  name        = "${local.prefixo}-negocio-trusted"
  description = "Mesma pergunta calculada direto na trusted (comparacao de custo)"
  workgroup   = aws_athena_workgroup.this.id
  database    = aws_glue_catalog_database.camada["trusted"].name
  query       = file("${path.module}/../../sql/consulta_negocio_trusted.sql")
}
