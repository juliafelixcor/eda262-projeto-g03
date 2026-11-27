-- Prova: a refined tem 71 linhas (36 Economy + 35 Business).
-- (DECISOES.md: seção 3, grão da refined)
SELECT class, COUNT(*) AS linhas, SUM(qtd_passagens) AS ofertas
FROM eda262_g03_refined.preco_por_periodo
GROUP BY class
ORDER BY class
