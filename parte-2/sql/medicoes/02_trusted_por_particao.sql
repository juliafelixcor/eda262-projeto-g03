-- Prova: registros por partição source_city (Delhi 61.343 ... Chennai 38.700;
-- maior / menor = 1,6x). (DECISOES.md: seção 5)
SELECT
    source_city,
    COUNT(*)                            AS registros,
    CAST(MAX(ingerido_em) AS VARCHAR)   AS ingerido_em
FROM eda262_g03_trusted.flights
GROUP BY source_city
ORDER BY source_city
