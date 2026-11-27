-- Voos, companhias e rotas distintos (números de apoio para a apresentação).
SELECT
    COUNT(DISTINCT flight)                                   AS voos_distintos,
    COUNT(DISTINCT airline)                                  AS companhias,
    COUNT(DISTINCT source_city || '->' || destination_city)  AS rotas
FROM eda262_g03_trusted.flights
