-- Mesma pergunta calculada direto na trusted (Parquet), para comparar o
-- volume escaneado com a refined e com o CSV da Parte 1.
SELECT
    departure_time,
    arrival_time,
    COUNT(*)             AS quantidade_passagens,
    ROUND(AVG(price), 2) AS preco_medio
FROM eda262_g03_trusted.flights
GROUP BY departure_time, arrival_time
ORDER BY preco_medio DESC
