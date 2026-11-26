-- Pergunta de negócio: o valor das passagens é influenciado pelo
-- horário de embarque e desembarque?
-- Média ponderada recomposta a partir da refined (soma_preco / qtd),
-- portanto o resultado é idêntico ao AVG(price) da Parte 1.
SELECT
    departure_time,
    arrival_time,
    SUM(qtd_passagens)                                        AS quantidade_passagens,
    ROUND(CAST(SUM(soma_preco) AS DOUBLE) / SUM(qtd_passagens), 2) AS preco_medio
FROM eda262_g03_refined.preco_por_periodo
GROUP BY departure_time, arrival_time
ORDER BY preco_medio DESC
