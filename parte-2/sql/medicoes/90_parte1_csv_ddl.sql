-- Tabela temporária com o schema da Parte 1, sobre o CSV sem compressão.
-- Criada e removida pelo coletar-evidencias.sh --parte1-csv; {{LOCAL}} é o
-- prefixo S3 temporário.
CREATE EXTERNAL TABLE IF NOT EXISTS eda262_g03_raw.medicao_parte1_csv (
    `index`          bigint,
    airline          string,
    flight           string,
    source_city      string,
    departure_time   string,
    stops            string,
    arrival_time     string,
    destination_city string,
    class            string,
    duration         double,
    days_left        int,
    price            int
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\')
LOCATION '{{LOCAL}}'
TBLPROPERTIES ('skip.header.line.count' = '1')
