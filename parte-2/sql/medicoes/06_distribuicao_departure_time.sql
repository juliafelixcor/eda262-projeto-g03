-- Prova: Late_Night tem 1.306 linhas (0,4%) -> partição por departure_time
-- geraria partição minúscula. Também mostra a fatia de Business por período.
-- (DECISOES.md: seção 5, alternativas descartadas)
SELECT
    departure_time,
    COUNT(*)                                                   AS linhas,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_do_total,
    count_if(class = 'Business')                               AS linhas_business,
    ROUND(100.0 * count_if(class = 'Business') / COUNT(*), 2)  AS pct_business
FROM eda262_g03_trusted.flights
GROUP BY departure_time
ORDER BY linhas
