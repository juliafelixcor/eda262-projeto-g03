-- Controle do principal fator de confusão (classe): a mesma pergunta
-- só para Economy. O filtro na coluna de partição faz o Athena ler
-- apenas class=Economy.
SELECT
    departure_time,
    arrival_time,
    qtd_passagens,
    preco_medio,
    preco_mediano
FROM eda262_g03_refined.preco_por_periodo
WHERE class = 'Economy'
ORDER BY preco_medio DESC
