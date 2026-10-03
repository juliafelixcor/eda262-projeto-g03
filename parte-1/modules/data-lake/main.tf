resource "aws_s3_bucket" "trusted" {
  bucket = "eda262-g03-lake-trusted"

  tags = {
    turma   = "eda262"
    grupo   = "g03"
    projeto = "engenharia-de-dados"
  }
}

resource "aws_s3_bucket_versioning" "trusted" {
  bucket = aws_s3_bucket.trusted.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_glue_catalog_database" "flights" {
  name = "eda262_g03_flights"

  tags = {
    turma   = "eda262"
    grupo   = "g03"
    projeto = "engenharia-de-dados"
  }
}

resource "aws_glue_catalog_table" "flights" {
  name          = "flights"
  database_name = aws_glue_catalog_database.flights.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "skip.header.line.count" = "1"
    "classification"         = "csv"
  }

  storage_descriptor {
    location = "s3://${aws_s3_bucket.trusted.bucket}/data/"
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

    columns {
      name = "index"
      type = "bigint"
    }

    columns {
      name = "airline"
      type = "string"
    }

    columns {
      name = "flight"
      type = "string"
    }

    columns {
      name = "source_city"
      type = "string"
    }

    columns {
      name = "departure_time"
      type = "string"
    }

    columns {
      name = "stops"
      type = "string"
    }

    columns {
      name = "arrival_time"
      type = "string"
    }

    columns {
      name = "destination_city"
      type = "string"
    }

    columns {
      name = "class"
      type = "string"
    }

    columns {
      name = "duration"
      type = "double"
    }

    columns {
      name = "days_left"
      type = "int"
    }

    columns {
      name = "price"
      type = "int"
    }
  }
}

resource "aws_athena_workgroup" "flights" {
  name = "eda262-g03-athena"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.trusted.bucket}/athena-results/"
    }
  }

  tags = {
    turma   = "eda262"
    grupo   = "g03"
    projeto = "engenharia-de-dados"
  }
}