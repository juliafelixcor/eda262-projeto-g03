-- trusted -> refined. A refined é recalculada inteira a cada carga
-- (no máximo 2 x 6 x 6 = 72 linhas); a ingestão apaga as partições
-- antes, então reexecutar não duplica.
INSERT INTO eda262_g03_refined.preco_por_periodo
SELECT
    departure_time,
    arrival_time,
    COUNT(*)                                       AS qtd_passagens,
    SUM(CAST(price AS BIGINT))                     AS soma_preco,
    ROUND(AVG(price), 2)                           AS preco_medio,
    CAST(approx_percentile(price, 0.5) AS INTEGER) AS preco_mediano,
    MIN(price)                                     AS preco_min,
    MAX(price)                                     AS preco_max,
    CAST(current_timestamp AS TIMESTAMP)           AS atualizado_em,
    class
FROM eda262_g03_trusted.flights
GROUP BY class, departure_time, arrival_time
