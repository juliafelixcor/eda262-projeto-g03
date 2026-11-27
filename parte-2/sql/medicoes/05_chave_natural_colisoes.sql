-- Prova: a chave natural candidata (10 atributos, sem o preço) se repete em
-- 1.555 combinações com preços diferentes -> não serve como chave, e o grão
-- é "1 oferta" (id_oferta). (DECISOES.md: seções 3 e 4)
WITH repetidas AS (
    SELECT COUNT(*) AS n, COUNT(DISTINCT price) AS precos_distintos
    FROM eda262_g03_trusted.flights
    GROUP BY airline, flight, source_city, destination_city, class, days_left,
             departure_time, arrival_time, stops, duration
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*)                         AS combinacoes_repetidas,
    count_if(precos_distintos > 1)   AS combinacoes_com_precos_diferentes,
    COALESCE(SUM(n), 0)              AS ofertas_envolvidas
FROM repetidas
