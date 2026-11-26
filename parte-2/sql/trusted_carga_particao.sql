-- raw -> trusted para UMA partição (source_city = '{{CIDADE}}').
-- Antes de rodar, a ingestão remove a partição do catálogo e apaga o
-- prefixo dela no S3; por isso reexecutar não duplica registros.
--
-- Regras de limpeza:
--   * TRIM em todos os textos; flight em maiúsculas; stops em minúsculas
--   * TRY_CAST nos numéricos (valor inválido vira NULL e é descartado)
--   * domínio: períodos, stops e class só com valores conhecidos
--   * faixa: price > 0, 0 < duration <= 50 h, days_left entre 1 e 365
--   * origem diferente de destino
--   * deduplicação por todos os atributos de negócio (fica o menor id)
INSERT INTO eda262_g03_trusted.flights
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
    WHERE TRIM(source_city) = '{{CIDADE}}'
),
valido AS (
    SELECT *
    FROM tipado
    WHERE id_oferta IS NOT NULL
      AND airline <> ''
      AND flight <> ''
      AND destination_city <> ''
      AND destination_city <> source_city
      AND departure_time IN ('Early_Morning', 'Morning', 'Afternoon', 'Evening', 'Night', 'Late_Night')
      AND arrival_time   IN ('Early_Morning', 'Morning', 'Afternoon', 'Evening', 'Night', 'Late_Night')
      AND stops IN ('zero', 'one', 'two_or_more')
      AND class IN ('Economy', 'Business')
      AND duration > 0 AND duration <= 50
      AND days_left BETWEEN 1 AND 365
      AND price > 0
),
dedup AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY airline, flight, source_city, departure_time, stops,
                         arrival_time, destination_city, class, duration,
                         days_left, price
            ORDER BY id_oferta
        ) AS rn
    FROM valido
)
SELECT
    id_oferta,
    airline,
    flight,
    departure_time,
    stops,
    CASE stops WHEN 'zero' THEN 0 WHEN 'one' THEN 1 ELSE 2 END AS qtd_escalas,
    arrival_time,
    destination_city,
    class,
    duration,
    days_left,
    price,
    CAST(current_timestamp AS TIMESTAMP) AS ingerido_em,
    source_city
FROM dedup
WHERE rn = 1
