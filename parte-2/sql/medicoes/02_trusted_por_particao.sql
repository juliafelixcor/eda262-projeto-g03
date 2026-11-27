-- Registros por partição source_city: equilíbrio entre partições
-- (DECISOES.md, seção 5).
SELECT
    source_city,
    COUNT(*)                            AS registros,
    CAST(MAX(ingerido_em) AS VARCHAR)   AS ingerido_em
FROM eda262_g03_trusted.flights
GROUP BY source_city
ORDER BY source_city
