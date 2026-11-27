-- Números de apoio para os slides: voos, companhias e rotas distintos.
-- (se algum desses números for citado na apresentação, a prova é esta)
SELECT
    COUNT(DISTINCT flight)                                   AS voos_distintos,
    COUNT(DISTINCT airline)                                  AS companhias,
    COUNT(DISTINCT source_city || '->' || destination_city)  AS rotas
FROM eda262_g03_trusted.flights
