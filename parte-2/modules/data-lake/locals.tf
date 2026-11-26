locals {
  # eda262-g03 (recursos com hífen) / eda262_g03 (Glue só aceita underscore)
  prefixo    = "eda262-${var.grupo}"
  prefixo_db = "eda262_${var.grupo}"

  camadas = toset(["raw", "trusted", "refined"])

  bucket_camada = { for c in local.camadas : c => "${local.prefixo}-lake-${c}" }
  database      = { for c in local.camadas : c => "${local.prefixo_db}_${c}" }

  # Matriz de acesso por camada (Lake Formation).
  # O engenheiro (quem roda o Terraform e a ingestão) tem acesso total às três.
  leitores_por_camada = {
    raw     = []
    trusted = ["cientista"]
    refined = ["cientista", "analista"]
  }

  personas = {
    analista  = "Consome apenas a camada refined (agregados de negocio)"
    cientista = "Consome as camadas trusted e refined"
  }

  grants_leitura = merge([
    for camada, personas in local.leitores_por_camada : {
      for p in personas : "${camada}-${p}" => { camada = camada, persona = p }
    }
  ]...)
}
