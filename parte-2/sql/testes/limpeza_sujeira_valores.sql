-- Lote de teste com sujeira plausível para as regras raw -> trusted.
-- O verifica.sh (critério 5b) roda o MESMO trusted_carga_particao.sql da
-- ingestão, trocando só a fonte (a tabela raw) por estas linhas.
-- Tudo em texto, como na raw. Resultado esperado: só os ids 1 e 2 passam,
-- e a linha 2 sai normalizada (Vistara / UK-2 / zero).
--
--  id   sujeira                          esperado
--  1    nenhuma                          aprovada
--  2    espaços e caixa trocada          aprovada e normalizada
--  3    duplicata exata do id 1          removida (deduplicação)
--  abc  id não numérico                  rejeitada
--  5    preço negativo                   rejeitada
--  6    preço em texto                   rejeitada
--  7    duração zero                     rejeitada
--  8    duração de 60 h                  rejeitada
--  9    days_left = 0                    rejeitada
--  10   classe fora do domínio           rejeitada
--  11   período de partida inválido      rejeitada
--  12   stops fora do domínio            rejeitada
--  13   origem igual ao destino          rejeitada
--  14   companhia vazia                  rejeitada
VALUES
    ('1',   'Vistara',   'UK-1',   'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Economy', '2.5', '10', '5000'),
    ('2',   ' Vistara ', ' uk-2 ', ' Delhi ', 'Morning', 'ZERO',  'Night',     'Mumbai', 'Economy', '2.5', '10', '6000'),
    ('3',   'Vistara',   'UK-1',   'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Economy', '2.5', '10', '5000'),
    ('abc', 'Vistara',   'UK-4',   'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Economy', '2.5', '10', '5000'),
    ('5',   'Vistara',   'UK-5',   'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Economy', '2.5', '10', '-10'),
    ('6',   'Vistara',   'UK-6',   'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Economy', '2.5', '10', 'mil'),
    ('7',   'Vistara',   'UK-7',   'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Economy', '0',   '10', '5000'),
    ('8',   'Vistara',   'UK-8',   'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Economy', '60',  '10', '5000'),
    ('9',   'Vistara',   'UK-9',   'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Economy', '2.5', '0',  '5000'),
    ('10',  'Vistara',   'UK-10',  'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Premium', '2.5', '10', '5000'),
    ('11',  'Vistara',   'UK-11',  'Delhi',   'Noon',    'zero',  'Afternoon', 'Mumbai', 'Economy', '2.5', '10', '5000'),
    ('12',  'Vistara',   'UK-12',  'Delhi',   'Morning', 'three', 'Afternoon', 'Mumbai', 'Economy', '2.5', '10', '5000'),
    ('13',  'Vistara',   'UK-13',  'Delhi',   'Morning', 'zero',  'Afternoon', 'Delhi',  'Economy', '2.5', '10', '5000'),
    ('14',  '',          'UK-14',  'Delhi',   'Morning', 'zero',  'Afternoon', 'Mumbai', 'Economy', '2.5', '10', '5000')
