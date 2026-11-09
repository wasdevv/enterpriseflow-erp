# ADR 004: dinheiro e valor ilegível

**Contexto.** Dinheiro em `Double` acumula erro. E um bug real surgiu nos testes: no Firebird 4+, `SUM` de `NUMERIC(18,2)` devolve `NUMERIC(38,2)` (INT128), e multiplicar dois `NUMERIC(18,2)` também. O driver do Free Pascal não reconhece esse tamanho e entrega o campo como `NULL`, sem erro. `AsCurrency` lia zero. Resultado: a exposição de crédito era sempre zero, e **o limite nunca era aplicado**, com a suíte unitária toda verde.

**Decisão.**
- `TMoney` guarda centavos, e `TQuantity`, milésimos, ambos em `Int64`. A conversão de `Currency` reinterpreta o inteiro escalado, sem passar por ponto flutuante, que em Win64 só teria a precisão de `Double`.
- Todo `SUM` financeiro tem `CAST(... AS NUMERIC(18,2))`.
- `IDbReader.Money` e `Qty` **lançam exceção em `NULL`**. As colunas são `NOT NULL` no schema, então `NULL` aqui é erro de consulta ou de driver. Valor desconhecido nunca vira zero.

**Consequências.** O próximo `SUM` sem `CAST` quebra de forma visível em vez de aprovar venda em silêncio (`UnreadableMoneyFailsInsteadOfBecomingZero`). Quem precisar de valor opcional tem de tratar o `NULL` antes de ler.
