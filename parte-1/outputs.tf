output "trusted_bucket_name" {
  value = module.data_lake.trusted_bucket_name
}

output "glue_database_name" {
  value = module.data_lake.glue_database_name
}

output "glue_table_name" {
  value = module.data_lake.glue_table_name
}

output "athena_workgroup_name" {
  value = module.data_lake.athena_workgroup_name
}