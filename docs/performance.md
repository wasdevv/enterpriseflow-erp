# Medição de índices

Cada índice foi medido antes de entrar no schema, como pede a especificação. Reproduza com `scripts/measure-indexes.py`.

## Método

- **Ambiente:** Firebird 5.0.4 (SuperServer) em WSL2, kernel 6.6, AMD Ryzen 7 5800XT, 16 threads. Consultas via `isql` local.
- **Dados:** `database/seeds/002_volume.sql`, sintético e proporcional ao cenário fictício: 8.000 SKUs em 2 depósitos, 146.000 movimentos (400/dia por um ano), 18.000 pedidos (1.500/mês por um ano), 32.400 parcelas, 16.200 eventos de outbox e 36.000 de auditoria. Banco de 65 MB.
- **Medida:** mesma consulta, sem e com o índice, depois de um aquecimento. Tempo é a mediana de 5 execuções, e depende da máquina; `Fetches` (acessos a páginas no cache) é o número mais estável para comparar.

Os dados são sintéticos: os números comparam planos, não preveem produção.

## Resultado

| Consulta | Índice candidato | Tempo sem (ms) | Tempo com (ms) | Fetches sem | Fetches com | Índice usado? | Decisão |
|---|---|---:|---:|---:|---:|---|---|
| Kardex de um item | `ix_movements_kardex` | 6 | 4 | 835 | 790 | sim | Rejeitado |
| Fila de pedidos por status | `ix_orders_queue` | 14 | 7 | 20.669 | 3.537 | sim | Adotado |
| Títulos vencidos | `ix_installments_open_due` | 30 | 25 | 46.469 | 15.100 | sim | Adotado |
| Worker pegando eventos da outbox | `ix_outbox_pending` | 7 | 3 | 17.580 | 464 | sim | Adotado |
| Histórico de uma entidade | `ix_audit_entity` | 12 | 3 | 37.426 | 362 | sim | Adotado |
| Busca de produto por trecho do nome | `ix_products_name_upper` | 14 | 14 | 15.139 | 15.153 | não | Rejeitado |

## Decisões

- **Kardex, rejeitado.** Os índices das chaves estrangeiras já resolvem o filtro: o ganho foi de 5% em fetches, numa tabela que recebe escrita o dia inteiro. O plano continua com `SORT`.
- **Busca por trecho, rejeitado.** `LIKE '%x%'` não usa índice, nem com expressão. Em 8.000 produtos, 14 ms não justificam outra solução.
- **Outbox e títulos, parciais.** Índice parcial (`WHERE`, novidade do Firebird 5) guarda só as linhas pendentes ou em aberto. Depois de um ano, quase tudo já foi enviado ou pago, e essas linhas não custam nada no índice. No caso da outbox, o custo deixa de crescer com o histórico.

## Armadilha encontrada

`WHERE (:status = '' OR o.status = :status)`, a forma comum de filtro opcional, impede o uso do índice: o plano não muda, o que aparece na medição. Por isso `SalesOrders` e `AuditTrail` só acrescentam o `WHERE` quando há filtro.

## Plano de cada consulta

```text
Kardex
  sem: PLAN SORT (JOIN (M INDEX (RDB$FOREIGN34, RDB$FOREIGN35), U INDEX (RDB$PRIMARY2)))
  com: PLAN SORT (JOIN (M INDEX (IX_MOVEMENTS_KARDEX), U INDEX (RDB$PRIMARY2)))

Fila de pedidos
  sem: PLAN SORT (HASH (JOIN (C NATURAL, O INDEX (RDB$FOREIGN62)), U NATURAL))
  com: PLAN JOIN (O ORDER IX_ORDERS_QUEUE, C INDEX (RDB$PRIMARY19), U INDEX (RDB$PRIMARY2))

Títulos vencidos
  sem: PLAN SORT (JOIN (HASH (JOIN (I NATURAL, T INDEX (RDB$PRIMARY85)), C NATURAL), N INDEX (RDB$PRIMARY79)))
  com: PLAN SORT (JOIN (HASH (JOIN (I INDEX (IX_INSTALLMENTS_OPEN_DUE), T INDEX (RDB$PRIMARY85)), C NATURAL), N INDEX (RDB$PRIMARY79)))

Outbox
  sem: PLAN (OUTBOX_EVENTS ORDER RDB$PRIMARY99)
  com: PLAN (OUTBOX_EVENTS ORDER IX_OUTBOX_PENDING INDEX (IX_OUTBOX_PENDING, IX_OUTBOX_PENDING))

Histórico de entidade
  sem: PLAN SORT (JOIN (A NATURAL, U INDEX (RDB$PRIMARY2)))
  com: PLAN SORT (JOIN (A INDEX (IX_AUDIT_ENTITY), U INDEX (RDB$PRIMARY2)))
```

## Como repetir

```bash
export EF_DB_HOST=127.0.0.1 EF_DB_PORT=53050 EF_DB_USER=SYSDBA EF_DB_PASSWORD=masterkey
export EF_DB_PATH=$HOME/.local/share/enterpriseflow-fb/perf.fdb EF_MIGRATIONS_DIR=database/migrations
build/fpc/efmigrate create && build/fpc/efmigrate migrate
build/fpc/efmigrate seed database/seeds/001_demo.sql
build/fpc/efmigrate seed database/seeds/002_volume.sql
python3 scripts/measure-indexes.py "$FIREBIRD/bin/isql" "127.0.0.1/53050:$EF_DB_PATH" SYSDBA masterkey
```

O script apaga os índices candidatos: use um banco só para medição.
