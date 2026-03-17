# 📦 Estoque Parado vs. Ruptura de Vendas — Case Distrimax

> **Área:** Business Intelligence · Melhoria Contínua  
> **Ferramentas:** SQL (SQLite) · Power BI · Análise de Causa Raiz  
> **Tipo:** Case com dados fictícios baseado em problemas reais de distribuição

---

## 🏢 Contexto

A **Distrimax** é uma distribuidora fictícia de produtos de higiene e limpeza com operação em 3 regiões (Sul, Sudeste e Centro-Oeste), faturamento anual de R$ 18M e aproximadamente 850 SKUs ativos, atendendo redes de farmácias e mercados.

O gestor de operações identificou duas reclamações simultâneas que pareciam contraditórias:

- O time **comercial** relatava perda de vendas por falta de produto — itens que sumiam do estoque antes do pedido chegar
- O time **financeiro** reclamava que o capital estava "preso" em estoque — produtos sem giro ocupando espaço e dinheiro

---

## ❓ Problema

> Como uma empresa pode ter **estoque em excesso** e **ruptura de vendas** ao mesmo tempo?

A hipótese inicial: a empresa trata todos os SKUs da mesma forma — mesmo prazo de reposição e mesmo nível de estoque mínimo — ignorando que 20% dos SKUs respondem por 80% da receita.

---

## 🗄️ Base de Dados

A base foi construída com dados fictícios mas realistas, estruturada em 4 tabelas:

| Tabela | Descrição | Linhas |
|--------|-----------|--------|
| `dim_sku_ok` | Cadastro de 100 SKUs com curva ABC, custo e política de reposição | 100 |
| `fato_vendas_ok` | Vendas mensais por SKU e região com receita perdida por ruptura | 3.600 |
| `fato_estoque_ok` | Snapshot semanal de estoque por SKU e região com status | 15.900 |
| `dim_meta_ok` | Política ideal de reposição por curva ABC | 3 |

---

## 🔍 Análise SQL

As queries foram desenvolvidas no SQLiteOnline e documentadas com explicação de cada técnica utilizada.

### Query 1 — Curva ABC
Classificação dos SKUs por participação na receita total, usando **window functions** para calcular o percentual acumulado.

```sql
SELECT
    s.sku_id,
    s.descricao,
    s.curva_abc,
    ROUND(SUM(v.receita_realizada), 2) AS receita_total,
    ROUND(SUM(v.receita_realizada) * 100.0 /
          SUM(SUM(v.receita_realizada)) OVER (), 2) AS pct_receita,
    ROUND(SUM(SUM(v.receita_realizada)) OVER (
          ORDER BY SUM(v.receita_realizada) DESC
          ROWS BETWEEN UNBOUNDED PRECEDING
          AND CURRENT ROW) * 100.0 /
          SUM(SUM(v.receita_realizada)) OVER (), 2) AS pct_acumulada
FROM fato_vendas_ok v
JOIN dim_sku_ok s ON v.sku_id = s.sku_id
GROUP BY s.sku_id, s.descricao, s.curva_abc
ORDER BY receita_total DESC;
```

### Query 2 — Ranking de Rupturas
Frequência de status crítico e ruptura por SKU e região, usando **CASE WHEN** para contar ocorrências por tipo de status.

```sql
SELECT
    e.sku_id,
    s.curva_abc,
    e.regiao,
    COUNT(*) AS total_registros,
    SUM(CASE WHEN e.status_estoque = 'Ruptura' THEN 1 ELSE 0 END) AS qtd_ruptura,
    SUM(CASE WHEN e.status_estoque = 'Crítico' THEN 1 ELSE 0 END) AS qtd_critico,
    ROUND(SUM(CASE WHEN e.status_estoque = 'Ruptura'
              THEN 1.0 ELSE 0 END) * 100 / COUNT(*), 1) AS pct_ruptura
FROM fato_estoque_ok e
JOIN dim_sku_ok s ON e.sku_id = s.sku_id
GROUP BY e.sku_id, s.curva_abc, e.regiao
ORDER BY qtd_ruptura DESC;
```

### Query 3 — Receita Perdida
Impacto financeiro das rupturas por curva ABC e categoria, revelando que **itens C nunca perdem receita** (estoque sempre em excesso).

```sql
SELECT
    s.curva_abc,
    s.categoria,
    ROUND(SUM(v.receita_perdida), 2) AS total_perdido,
    ROUND(SUM(v.receita_realizada), 2) AS total_realizado,
    ROUND(SUM(v.receita_perdida) * 100.0 /
          (SUM(v.receita_perdida) + SUM(v.receita_realizada)), 2) AS pct_perda
FROM fato_vendas_ok v
JOIN dim_sku_ok s ON v.sku_id = s.sku_id
GROUP BY s.curva_abc, s.categoria
ORDER BY total_perdido DESC;
```

### Query 4 — Estoque Atual vs. Política Ideal
Comparativo entre a cobertura praticada e a meta recomendada — **a query que prova o desalinhamento da política atual**.

```sql
SELECT
    s.curva_abc,
    ROUND(AVG(e.dias_cobertura), 1) AS cobertura_media_atual,
    ROUND(AVG(e.estoque_fisico), 0) AS estoque_medio_atual,
    m.estoque_minimo_recomendado_dias AS meta_cobertura,
    m.frequencia_revisao,
    m.politica_reposicao
FROM fato_estoque_ok e
JOIN dim_sku_ok s ON e.sku_id = s.sku_id
JOIN dim_meta_ok m ON s.curva_abc = m.curva_abc
GROUP BY s.curva_abc, m.estoque_minimo_recomendado_dias,
         m.frequencia_revisao, m.politica_reposicao
ORDER BY s.curva_abc;
```

---

## 🔬 Diagnóstico — Ferramentas de Qualidade

### Curva ABC
Os 20 SKUs da curva A representam **~80% da receita total**, mas operam com cobertura média de apenas **10 dias** — muito abaixo da meta de 30 a 45 dias.

### Diagrama de Ishikawa
Análise de causa raiz da ruptura nos itens A:

| Categoria | Causa identificada |
|-----------|-------------------|
| Método | Política de reposição uniforme para todos os SKUs |
| Medição | Estoque mínimo calculado sem considerar giro real |
| Gestão | Ausência de revisão periódica por curva ABC |
| Material | Prazo de reposição subestimado para itens de alta demanda |

### Matriz GUT

| Problema | Gravidade | Urgência | Tendência | GUT |
|----------|-----------|----------|-----------|-----|
| Ruptura itens A | 5 | 5 | 5 | 125 |
| Excesso itens C | 4 | 3 | 4 | 48 |
| Política uniforme | 5 | 4 | 5 | 100 |

---

## 📊 Dashboard Power BI

### Página 1 — Diagnóstico

![Dashboard Diagnóstico](assets/dashboard_diagnostico.png)

**Principais achados:**
- **R$ 194Mi** em receita perdida por ruptura no ano
- Curva A com **10 dias** de cobertura média contra meta de 30-45 dias
- Curva C com **1.363 dias** de cobertura — capital completamente imobilizado
- Categoria Limpeza concentra a maior perda: **R$ 64Mi**

### Página 2 — Solução

![Dashboard Solução](assets/dashboard_solucao.png)

**Impacto projetado com nova política:**
- Curva A: cobertura sobe de 10 para **38 dias**
- Curva B: cobertura ajusta de 79 para **22 dias**
- Curva C: cobertura reduz de 1.363 para **12 dias**

---

## ✅ Solução — Nova Política de Reposição

| Curva | Estoque Mínimo | Frequência de Revisão | Política | Meta (dias) |
|-------|---------------|----------------------|----------|-------------|
| A | 30 a 45 dias | Semanal | Reposição contínua por demanda | 45 |
| B | 15 a 30 dias | Quinzenal | Reposição por ponto de pedido | 30 |
| C | 7 a 15 dias | Mensal | Reposição periódica mínima | 15 |

### Impacto estimado
- **Receita recuperável:** ~78% da receita perdida nos itens A
- **Redução de estoque curva C:** -23%
- **Redução de ruptura curva A:** -18%

---

## 📁 Estrutura do Repositório

```
distrimax-case/
├── README.md
├── README_EN.md
├── data/
│   ├── dim_sku_ok.csv
│   ├── fato_vendas_ok.csv
│   ├── fato_estoque_ok.csv
│   └── dim_meta_ok.csv
├── sql/
│   └── queries_distrimax.sql
└── assets/
    ├── dashboard_diagnostico.png
    └── dashboard_solucao.png
```

---

## 👤 Autor

Desenvolvido como case de portfólio em BI e Melhoria Contínua.  
[LinkedIn](#) · [Portfólio](#)
