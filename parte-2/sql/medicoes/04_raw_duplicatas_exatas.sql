-- Prova: 0 duplicatas exatas na raw (todos os 11 atributos de negócio
-- iguais, após o mesmo TRIM/normalização da trusted). (DECISOES.md: seções 3 e 4)
WITH normalizado AS (
    SELECT
        TRIM(airline) AS airline, UPPER(TRIM(flight)) AS flight,
        TRIM(source_city) AS source_city, TRIM(departure_time) AS departure_time,
        LOWER(TRIM(stops)) AS stops, TRIM(arrival_time) AS arrival_time,
        TRIM(destination_city) AS destination_city, TRIM("class") AS class,
        TRIM(duration) AS duration, TRIM(days_left) AS days_left, TRIM(price) AS price
    FROM eda262_g03_raw.flights
),
grupos AS (
    SELECT COUNT(*) AS n
    FROM normalizado
    GROUP BY airline, flight, source_city, departure_time, stops, arrival_time,
             destination_city, class, duration, days_left, price
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*)                AS grupos_duplicados,
    COALESCE(SUM(n - 1), 0) AS linhas_excedentes
FROM grupos
