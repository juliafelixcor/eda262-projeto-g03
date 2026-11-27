-- Prova: a consulta de negócio da Parte 1 (parte-1/README.md), no CSV sem
-- compressão, escaneia 24.946.485 bytes. Roda na tabela temporária criada
-- por 90_parte1_csv_ddl.sql. (DECISOES.md: seções 6 e 7)
SELECT
    departure_time,
    arrival_time,
    COUNT(*)             AS quantidade_passagens,
    ROUND(AVG(price), 2) AS preco_medio
FROM eda262_g03_raw.medicao_parte1_csv
GROUP BY departure_time, arrival_time
ORDER BY preco_medio DESC
