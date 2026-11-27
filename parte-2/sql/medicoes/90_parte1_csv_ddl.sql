-- Reprodução da Parte 1 para medir o custo do CSV sem compressão.
-- Tabela TEMPORÁRIA criada e removida pelo coletar-evidencias.sh
-- (--parte1-csv), com o mesmo schema da tabela da Parte 1.
-- {{LOCAL}} é substituído pelo prefixo S3 temporário.
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
