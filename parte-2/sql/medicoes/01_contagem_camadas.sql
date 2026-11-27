-- Prova: 300.153 linhas na raw, 300.153 na trusted com 300.153 id_oferta
-- distintos (chave única), e a refined somando as mesmas 300.153 ofertas
-- em 71 linhas. (DECISOES.md: resumo, seções 3 e 4)
SELECT 'raw' AS camada, COUNT(*) AS linhas, CAST(NULL AS BIGINT) AS id_oferta_distintos, CAST(NULL AS BIGINT) AS ofertas_representadas
FROM eda262_g03_raw.flights
UNION ALL
SELECT 'trusted', COUNT(*), COUNT(DISTINCT id_oferta), COUNT(*)
FROM eda262_g03_trusted.flights
UNION ALL
SELECT 'refined', COUNT(*), CAST(NULL AS BIGINT), SUM(qtd_passagens)
FROM eda262_g03_refined.preco_por_periodo
