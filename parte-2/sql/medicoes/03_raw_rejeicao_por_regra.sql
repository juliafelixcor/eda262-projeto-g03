-- Prova: quantas linhas da raw cada regra de limpeza da trusted rejeitaria.
-- Mesma tipagem e mesmas regras de trusted_carga_particao.sql; cada coluna
-- conta a regra isoladamente (uma linha pode falhar em mais de uma).
-- (DECISOES.md: seção 8, "Regras de limpeza")
WITH tipado AS (
    SELECT
        TRY_CAST(TRIM("index") AS BIGINT)    AS id_oferta,
        TRIM(airline)                        AS airline,
        UPPER(TRIM(flight))                  AS flight,
        TRIM(source_city)                    AS source_city,
        TRIM(departure_time)                 AS departure_time,
        LOWER(TRIM(stops))                   AS stops,
        TRIM(arrival_time)                   AS arrival_time,
        TRIM(destination_city)               AS destination_city,
        TRIM("class")                        AS class,
        TRY_CAST(TRIM(duration) AS DOUBLE)   AS duration,
        TRY_CAST(TRIM(days_left) AS INTEGER) AS days_left,
        TRY_CAST(TRIM(price) AS INTEGER)     AS price
    FROM eda262_g03_raw.flights
)
SELECT
    COUNT(*)                                                                      AS linhas_raw,
    count_if(id_oferta IS NULL)                                                   AS id_invalido,
    count_if(COALESCE(airline, '') = '')                                          AS airline_vazio,
    count_if(COALESCE(flight, '') = '')                                           AS flight_vazio,
    count_if(COALESCE(source_city, '') = '')                                      AS origem_vazia,
    count_if(COALESCE(destination_city, '') = '')                                 AS destino_vazio,
    count_if(destination_city = source_city)                                      AS origem_igual_destino,
    count_if(COALESCE(departure_time, '') NOT IN ('Early_Morning', 'Morning', 'Afternoon', 'Evening', 'Night', 'Late_Night')) AS partida_fora_dominio,
    count_if(COALESCE(arrival_time, '')   NOT IN ('Early_Morning', 'Morning', 'Afternoon', 'Evening', 'Night', 'Late_Night')) AS chegada_fora_dominio,
    count_if(COALESCE(stops, '') NOT IN ('zero', 'one', 'two_or_more'))           AS stops_fora_dominio,
    count_if(COALESCE(class, '') NOT IN ('Economy', 'Business'))                  AS class_fora_dominio,
    count_if(duration IS NULL OR duration <= 0 OR duration > 50)                  AS duracao_invalida,
    count_if(days_left IS NULL OR days_left < 1 OR days_left > 365)               AS days_left_invalido,
    count_if(price IS NULL OR price <= 0)                                         AS preco_invalido
FROM tipado
