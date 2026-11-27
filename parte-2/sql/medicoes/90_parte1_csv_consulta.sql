-- Consulta de negócio da Parte 1 (parte-1/README.md) sobre o CSV sem
-- compressão, para comparar o custo com a Parte 2 (DECISOES.md, seções 6 e 7).
SELECT
    departure_time,
    arrival_time,
    COUNT(*)             AS quantidade_passagens,
    ROUND(AVG(price), 2) AS preco_medio
FROM eda262_g03_raw.medicao_parte1_csv
GROUP BY departure_time, arrival_time
ORDER BY preco_medio DESC
