output "buckets" {
  description = "Buckets do Data Lake por camada"
  value       = module.data_lake.buckets
}

output "athena_results_bucket_name" {
  value = module.data_lake.athena_results_bucket_name
}

output "glue_databases" {
  description = "Databases do Glue Data Catalog por camada"
  value       = module.data_lake.glue_databases
}

output "glue_tables" {
  description = "Tabelas por camada (database.tabela)"
  value       = module.data_lake.glue_tables
}

output "athena_workgroup_name" {
  value = module.data_lake.athena_workgroup_name
}

output "role_analista_arn" {
  value = module.data_lake.role_analista_arn
}

output "role_cientista_arn" {
  value = module.data_lake.role_cientista_arn
}

output "lakeformation_admin_arn" {
  value = module.data_lake.lakeformation_admin_arn
}
