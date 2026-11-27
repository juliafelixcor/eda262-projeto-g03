output "bucket_state" {
  value = aws_s3_bucket.state.bucket
}

output "tabela_lock" {
  value = aws_dynamodb_table.lock.name
}

output "proximo_passo" {
  description = "Comando de init da stack principal apontando para este backend"
  value       = "terraform -chdir=parte-2 init -backend-config=\"bucket=${aws_s3_bucket.state.bucket}\" -backend-config=\"dynamodb_table=${aws_dynamodb_table.lock.name}\" -backend-config=\"region=${var.aws_region}\""
}
