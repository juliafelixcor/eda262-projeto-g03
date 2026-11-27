-- COUNT(*) na trusted: o Athena responde pelos metadados do Parquet, sem
-- ler dados (DECISOES.md, seção 6).
SELECT COUNT(*) AS linhas
FROM eda262_g03_trusted.flights
