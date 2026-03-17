-- ============================================================
-- CASE: Estoque parado vs. Ruptura de vendas
-- Empresa fictícia: Distrimax
-- Ferramenta: SQLiteOnline
-- Autor: [Seu Nome]
-- ============================================================
-- OBSERVAÇÃO: O SQLiteOnline exibe "UM" para a curva A
-- mas o valor real no banco é "A" — apenas visual do sistema.
-- ============================================================


-- ------------------------------------------------------------
-- SETUP: Recriar tabelas com nomes de colunas corretos
-- (necessário pois o SQLiteOnline importa como c1, c2, c3...)
-- ------------------------------------------------------------

CREATE TABLE dim_sku_ok AS
SELECT
    c1 AS sku_id,
    c2 AS descricao,
    c3 AS categoria,
    c4 AS fornecedor,
    CAST(c5 AS REAL) AS custo_unitario,
    CAST(c6 AS REAL) AS preco_venda,
    CASE c7 WHEN 'UM' THEN 'A' ELSE c7 END AS curva_abc,
    CAST(c8 AS INTEGER) AS dias_reposicao,
    CAST(c9 AS INTEGER) AS estoque_minimo_atual
FROM dim_sku
WHERE c1 != 'sku_id';

CREATE TABLE fato_vendas_ok AS
SELECT
    c1 AS data_venda,
    c2 AS sku_id,
    c3 AS regiao,
    CAST(c4 AS INTEGER) AS qtd_vendida,
    CAST(c5 AS INTEGER) AS qtd_perdida_ruptura,
    CAST(c6 AS REAL) AS receita_realizada,
    CAST(c7 AS REAL) AS receita_perdida,
    c8 AS canal
FROM fato_vendas
WHERE c1 != 'data_venda';

CREATE TABLE fato_estoque_ok AS
SELECT
    c1 AS data,
    c2 AS sku_id,
    c3 AS regiao,
    CAST(c4 AS INTEGER) AS estoque_fisico,
    CAST(c5 AS REAL) AS demanda_media_diaria,
    CAST(c6 AS INTEGER) AS ponto_pedido,
    c7 AS status_estoque,
    CAST(c8 AS REAL) AS dias_cobertura
FROM fato_estoque_diario
WHERE c1 != 'data';

CREATE TABLE dim_meta_ok AS
SELECT
    c1 AS curva_abc,
    c2 AS estoque_minimo_recomendado_dias,
    c3 AS frequencia_revisao,
    c4 AS politica_reposicao,
    CAST(c5 AS INTEGER) AS meta_cobertura_dias
FROM dim_meta_reposicao
WHERE c1 != 'curva_abc';


-- ------------------------------------------------------------
-- QUERY 1: Curva ABC — participação de cada SKU na receita
-- ------------------------------------------------------------
-- Objetivo: classificar os SKUs por impacto de receita e
-- calcular o percentual acumulado (lógica 80/15/5%)
-- Técnica: window functions com SUM() OVER()
-- ------------------------------------------------------------

SELECT
    s.sku_id,
    s.descricao,
    s.curva_abc,
    s.categoria,
    ROUND(SUM(v.receita_realizada), 2)                          AS receita_total,
    ROUND(SUM(v.receita_realizada) * 100.0 /
          SUM(SUM(v.receita_realizada)) OVER (), 2)             AS pct_receita,
    ROUND(SUM(SUM(v.receita_realizada)) OVER (
          ORDER BY SUM(v.receita_realizada) DESC
          ROWS BETWEEN UNBOUNDED PRECEDING
          AND CURRENT ROW) * 100.0 /
          SUM(SUM(v.receita_realizada)) OVER (), 2)             AS pct_acumulada
FROM fato_vendas_ok v
JOIN dim_sku_ok s ON v.sku_id = s.sku_id
GROUP BY s.sku_id, s.descricao, s.curva_abc, s.categoria
ORDER BY receita_total DESC;


-- ------------------------------------------------------------
-- QUERY 2: Ranking de rupturas por SKU e região
-- ------------------------------------------------------------
-- Objetivo: identificar quais SKUs e regiões concentram
-- os maiores episódios de ruptura e estado crítico de estoque
-- Técnica: CASE WHEN para contar ocorrências por status
-- ------------------------------------------------------------

SELECT
    e.sku_id,
    s.descricao,
    s.curva_abc,
    e.regiao,
    COUNT(*)                                                     AS total_registros,
    SUM(CASE WHEN e.status_estoque = 'Ruptura'
             THEN 1 ELSE 0 END)                                  AS qtd_ruptura,
    SUM(CASE WHEN e.status_estoque = 'Crítico'
             THEN 1 ELSE 0 END)                                  AS qtd_critico,
    ROUND(SUM(CASE WHEN e.status_estoque = 'Ruptura'
              THEN 1.0 ELSE 0 END) * 100 / COUNT(*), 1)         AS pct_ruptura
FROM fato_estoque_ok e
JOIN dim_sku_ok s ON e.sku_id = s.sku_id
GROUP BY e.sku_id, s.descricao, s.curva_abc, e.regiao
ORDER BY qtd_ruptura DESC;


-- ------------------------------------------------------------
-- QUERY 3: Receita perdida por curva ABC e categoria
-- ------------------------------------------------------------
-- Objetivo: quantificar o impacto financeiro das rupturas
-- e mostrar que itens C nunca perdem receita (estoque em excesso)
-- Técnica: agregação com cálculo de percentual de perda
-- ------------------------------------------------------------

SELECT
    s.curva_abc,
    s.categoria,
    ROUND(SUM(v.receita_perdida), 2)                            AS total_perdido,
    ROUND(SUM(v.receita_realizada), 2)                          AS total_realizado,
    ROUND(SUM(v.receita_perdida) * 100.0 /
          (SUM(v.receita_perdida) +
           SUM(v.receita_realizada)), 2)                        AS pct_perda
FROM fato_vendas_ok v
JOIN dim_sku_ok s ON v.sku_id = s.sku_id
GROUP BY s.curva_abc, s.categoria
ORDER BY total_perdido DESC;


-- ------------------------------------------------------------
-- QUERY 4: Estoque atual vs. política ideal por curva ABC
-- ------------------------------------------------------------
-- Objetivo: comparar a cobertura de estoque praticada com
-- a meta recomendada — revela o desalinhamento da política atual
-- Resultado esperado:
--   Curva A → cobertura ~1 dia  (meta: 30 a 45 dias) CRÍTICO
--   Curva B → cobertura ~8 dias (meta: 15 a 30 dias) ABAIXO
--   Curva C → cobertura ~136 dias (meta: 7 a 15 dias) EXCESSO
-- ------------------------------------------------------------

SELECT
    s.curva_abc,
    ROUND(AVG(e.dias_cobertura), 1)       AS cobertura_media_atual,
    ROUND(AVG(e.estoque_fisico), 0)       AS estoque_medio_atual,
    ROUND(AVG(s.estoque_minimo_atual), 0) AS minimo_configurado,
    m.estoque_minimo_recomendado_dias     AS meta_cobertura,
    m.frequencia_revisao,
    m.politica_reposicao
FROM fato_estoque_ok e
JOIN dim_sku_ok s ON e.sku_id = s.sku_id
JOIN dim_meta_ok m ON s.curva_abc = m.curva_abc
GROUP BY s.curva_abc,
         m.estoque_minimo_recomendado_dias,
         m.frequencia_revisao,
         m.politica_reposicao
ORDER BY s.curva_abc;
