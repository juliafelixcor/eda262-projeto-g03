output "buckets" {
  description = "Buckets do Data Lake por camada"
  value       = { for c, b in aws_s3_bucket.camada : c => b.bucket }
}

output "athena_results_bucket_name" {
  value = aws_s3_bucket.athena_results.bucket
}

output "glue_databases" {
  value = { for c, d in aws_glue_catalog_database.camada : c => d.name }
}

output "glue_tables" {
  value = {
    raw     = "${aws_glue_catalog_table.raw_flights.database_name}.${aws_glue_catalog_table.raw_flights.name}"
    trusted = "${aws_glue_catalog_table.trusted_flights.database_name}.${aws_glue_catalog_table.trusted_flights.name}"
    refined = "${aws_glue_catalog_table.refined_preco_por_periodo.database_name}.${aws_glue_catalog_table.refined_preco_por_periodo.name}"
  }
}

output "athena_workgroup_name" {
  value = aws_athena_workgroup.this.name
}

output "role_analista_arn" {
  value = aws_iam_role.persona["analista"].arn
}

output "role_cientista_arn" {
  value = aws_iam_role.persona["cientista"].arn
}

output "lakeformation_admin_arn" {
  value = local.engenheiro_arn
}
