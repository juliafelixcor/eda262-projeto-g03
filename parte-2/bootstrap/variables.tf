variable "aws_region" {
  description = "Região AWS do backend (a mesma de parte-2/backend.tf)"
  type        = string
  default     = "us-east-1"
}

variable "grupo" {
  description = "Identificador do grupo no formato gNN"
  type        = string
  default     = "g03"

  validation {
    condition     = can(regex("^g[0-9]{2}$", var.grupo))
    error_message = "O grupo deve seguir o formato gNN (ex.: g03)."
  }
}

variable "bucket_state" {
  description = <<-EOT
    Nome do bucket do state. Vazio = eda262-<grupo>-terraform-state.
    Nomes de bucket são globais: se o padrão já existir em outra conta,
    informe outro nome aqui e o mesmo nome no init de parte-2/.
  EOT
  type        = string
  default     = ""
}
