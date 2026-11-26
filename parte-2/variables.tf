variable "aws_region" {
  description = "Região AWS utilizada pelo projeto"
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
