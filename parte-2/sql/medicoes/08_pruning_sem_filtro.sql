-- Par com 09_pruning_delhi.sql: mesma consulta sem filtro de partição,
-- para comparar os bytes escaneados (DECISOES.md, seção 5).
SELECT AVG(price) AS preco_medio
FROM eda262_g03_trusted.flights
