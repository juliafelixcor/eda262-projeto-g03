-- Dentro de cada classe, maior e menor preço médio entre as combinações de
-- período com pelo menos 100 ofertas (DECISOES.md, seção 11).
SELECT
    class,
    COUNT(*)                                       AS combinacoes_consideradas,
    MAX(preco_medio)                               AS maior_preco_medio,
    MIN(preco_medio)                               AS menor_preco_medio,
    ROUND(MAX(preco_medio) / MIN(preco_medio), 2)  AS razao,
    ROUND(MAX(preco_medio) - MIN(preco_medio), 2)  AS diferenca_absoluta
FROM eda262_g03_refined.preco_por_periodo
WHERE qtd_passagens >= 100
GROUP BY class
ORDER BY class
