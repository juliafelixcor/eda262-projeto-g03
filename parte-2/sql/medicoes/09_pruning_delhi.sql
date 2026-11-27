-- Prova (par com 08): bytes escaneados COM filtro na coluna de partição;
-- o Athena lê só source_city=Delhi. DECISOES.md seção 5: 78,25 KB (-79%).
SELECT AVG(price) AS preco_medio
FROM eda262_g03_trusted.flights
WHERE source_city = 'Delhi'
