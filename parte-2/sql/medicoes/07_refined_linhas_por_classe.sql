-- Linhas da refined por classe (DECISOES.md, seção 3).
SELECT class, COUNT(*) AS linhas, SUM(qtd_passagens) AS ofertas
FROM eda262_g03_refined.preco_por_periodo
GROUP BY class
ORDER BY class
