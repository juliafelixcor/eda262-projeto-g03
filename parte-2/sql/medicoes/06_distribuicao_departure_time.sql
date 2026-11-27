-- Linhas e fatia de Business por período de partida. Mostra o tamanho que
-- teria uma partição por departure_time (DECISOES.md, seção 5).
SELECT
    departure_time,
    COUNT(*)                                                   AS linhas,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_do_total,
    count_if(class = 'Business')                               AS linhas_business,
    ROUND(100.0 * count_if(class = 'Business') / COUNT(*), 2)  AS pct_business
FROM eda262_g03_trusted.flights
GROUP BY departure_time
ORDER BY linhas
