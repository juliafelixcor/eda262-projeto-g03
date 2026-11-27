-- Linhas por camada, id_oferta distintos na trusted e ofertas somadas na
-- refined. Sustenta o grão e a chave (DECISOES.md, seções 3 e 4).
SELECT 'raw' AS camada, COUNT(*) AS linhas, CAST(NULL AS BIGINT) AS id_oferta_distintos, CAST(NULL AS BIGINT) AS ofertas_representadas
FROM eda262_g03_raw.flights
UNION ALL
SELECT 'trusted', COUNT(*), COUNT(DISTINCT id_oferta), COUNT(*)
FROM eda262_g03_trusted.flights
UNION ALL
SELECT 'refined', COUNT(*), CAST(NULL AS BIGINT), SUM(qtd_passagens)
FROM eda262_g03_refined.preco_por_periodo
