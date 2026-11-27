-- Par com 08_pruning_sem_filtro.sql: com filtro na coluna de partição, o
-- Athena lê só source_city=Delhi (DECISOES.md, seção 5).
SELECT AVG(price) AS preco_medio
FROM eda262_g03_trusted.flights
WHERE source_city = 'Delhi'
