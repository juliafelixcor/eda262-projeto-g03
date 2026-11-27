-- Prova: COUNT(*) na trusted é respondido pelos metadados do Parquet
-- (0 bytes escaneados). (DECISOES.md: seção 6)
SELECT COUNT(*) AS linhas
FROM eda262_g03_trusted.flights
