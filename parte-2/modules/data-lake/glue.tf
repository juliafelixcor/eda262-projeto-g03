# ------------------------------------------------------------
# Glue Data Catalog — uma database por camada.
# Schemas declarados aqui (sem Crawler).
# ------------------------------------------------------------

resource "aws_glue_catalog_database" "camada" {
  for_each = local.database

  name        = each.value
  description = "Camada ${each.key} do Data Lake de passagens aereas (${var.grupo})"

  # As databases precisam nascer DEPOIS das configurações do Lake Formation:
  # assim não herdam o grant padrão a IAM_ALLOWED_PRINCIPALS e o acesso
  # passa a ser controlado de fato pelo Lake Formation.
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

locals {
  # RAW: tudo string, exatamente como vem no CSV. Tipagem e limpeza
  # acontecem na passagem para a trusted.
  colunas_raw = [
    "index", "airline", "flight", "source_city", "departure_time", "stops",
    "arrival_time", "destination_city", "class", "duration", "days_left", "price",
  ]

  colunas_trusted = [
    { name = "id_oferta", type = "bigint", comment = "index do CSV original (unico por oferta)" },
    { name = "airline", type = "string", comment = "" },
    { name = "flight", type = "string", comment = "" },
    { name = "departure_time", type = "string", comment = "periodo de partida" },
    { name = "stops", type = "string", comment = "zero / one / two_or_more" },
    { name = "qtd_escalas", type = "int", comment = "0, 1 ou 2 (2 = duas ou mais)" },
    { name = "arrival_time", type = "string", comment = "periodo de chegada" },
    { name = "destination_city", type = "string", comment = "" },
    { name = "class", type = "string", comment = "Economy / Business" },
    { name = "duration", type = "double", comment = "duracao em horas" },
    { name = "days_left", type = "int", comment = "dias de antecedencia da compra" },
    { name = "price", type = "int", comment = "preco da passagem" },
    { name = "ingerido_em", type = "timestamp", comment = "momento da (re)carga da particao" },
  ]

  colunas_refined = [
    { name = "departure_time", type = "string", comment = "" },
    { name = "arrival_time", type = "string", comment = "" },
    { name = "qtd_passagens", type = "bigint", comment = "" },
    { name = "soma_preco", type = "bigint", comment = "permite recompor a media ponderada entre classes" },
    { name = "preco_medio", type = "double", comment = "" },
    { name = "preco_mediano", type = "int", comment = "approx_percentile 0.5" },
    { name = "preco_min", type = "int", comment = "" },
    { name = "preco_max", type = "int", comment = "" },
    { name = "atualizado_em", type = "timestamp", comment = "" },
  ]

  parquet = {
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    serde         = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
  }
}

# ---------------------------- RAW ----------------------------

resource "aws_glue_catalog_table" "raw_flights" {
  name          = "flights"
  database_name = aws_glue_catalog_database.camada["raw"].name
  table_type    = "EXTERNAL_TABLE"
  description   = "Arquivo bruto (CSV gzip) como recebido da fonte"

  parameters = {
    "EXTERNAL"               = "TRUE"
    "classification"         = "csv"
    "compressionType"        = "gzip"
    "skip.header.line.count" = "1"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.camada["raw"].bucket}/flights/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"

      parameters = {
        "separatorChar" = ","
        "quoteChar"     = "\""
        "escapeChar"    = "\\"
      }
    }

    dynamic "columns" {
      for_each = local.colunas_raw
      content {
        name = columns.value
        type = "string"
      }
    }
  }
}

# -------------------------- TRUSTED --------------------------
# Grão: uma oferta de passagem. Parquet + partição por cidade de origem.

resource "aws_glue_catalog_table" "trusted_flights" {
  name          = "flights"
  database_name = aws_glue_catalog_database.camada["trusted"].name
  table_type    = "EXTERNAL_TABLE"
  description   = "Ofertas de passagem limpas e tipadas; grao = 1 oferta (id_oferta)"

  parameters = {
    "EXTERNAL"            = "TRUE"
    "classification"      = "parquet"
    "parquet.compression" = "SNAPPY"
  }

  partition_keys {
    name    = "source_city"
    type    = "string"
    comment = "cidade de origem; unidade de ingestao e de backfill"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.camada["trusted"].bucket}/flights/"
    input_format  = local.parquet.input_format
    output_format = local.parquet.output_format

    ser_de_info {
      serialization_library = local.parquet.serde
    }

    dynamic "columns" {
      for_each = local.colunas_trusted
      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = columns.value.comment
      }
    }
  }
}

# -------------------------- REFINED --------------------------
# Grão: classe x período de partida x período de chegada.

resource "aws_glue_catalog_table" "refined_preco_por_periodo" {
  name          = "preco_por_periodo"
  database_name = aws_glue_catalog_database.camada["refined"].name
  table_type    = "EXTERNAL_TABLE"
  description   = "Preco por combinacao de periodos; grao = class x departure_time x arrival_time"

  parameters = {
    "EXTERNAL"            = "TRUE"
    "classification"      = "parquet"
    "parquet.compression" = "SNAPPY"
  }

  partition_keys {
    name = "class"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.camada["refined"].bucket}/preco_por_periodo/"
    input_format  = local.parquet.input_format
    output_format = local.parquet.output_format

    ser_de_info {
      serialization_library = local.parquet.serde
    }

    dynamic "columns" {
      for_each = local.colunas_refined
      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = columns.value.comment
      }
    }
  }
}
