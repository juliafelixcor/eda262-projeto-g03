output "trusted_bucket_name" {
  description = "Nome do bucket trusted do Data Lake"
  value       = aws_s3_bucket.trusted.bucket
}

output "glue_database_name" {
  description = "Nome do banco no Glue Data Catalog"
  value       = aws_glue_catalog_database.flights.name
}