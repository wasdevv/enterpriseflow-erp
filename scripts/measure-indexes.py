#!/usr/bin/env python3
"""Mede cada indice candidato: mesma consulta, com e sem o indice, em banco com volume sintetico.

Roda isql com SET PLAN/SET STATS e imprime uma tabela em Markdown. Cada consulta roda varias
vezes e o tempo e a mediana. Fetches e deterministico; o tempo depende da maquina.

Uso: measure-indexes.py <isql> <dsn> <usuario> <senha>
"""
import re
import statistics
import subprocess
import sys

ISQL, DSN, USER, PASSWORD = sys.argv[1:5]
RUNS = 5

CANDIDATES = [
    {
        "name": "ix_movements_kardex",
        "ddl": "CREATE DESCENDING INDEX ix_movements_kardex ON stock_movements (product_id, warehouse_id, id)",
        "query": "SELECT FIRST 1000 m.occurred_at, m.movement_type, m.quantity, u.username FROM stock_movements m "
                 "JOIN users u ON u.id = m.user_id WHERE m.product_id = (SELECT MIN(id) + 3500 FROM products WHERE sku STARTING WITH 'VOL-') "
                 "AND m.warehouse_id = (SELECT MIN(id) FROM warehouses) ORDER BY m.id DESC",
        "label": "Kardex de um item",
    },
    {
        "name": "ix_orders_queue",
        "ddl": "CREATE DESCENDING INDEX ix_orders_queue ON sales_orders (status, updated_at)",
        "query": "SELECT FIRST 500 o.id, c.name, o.status, o.total, u.username, o.updated_at FROM sales_orders o "
                 "JOIN customers c ON c.id = o.customer_id JOIN users u ON u.id = o.seller_id "
                 "WHERE o.status = 'RESERVED' ORDER BY o.updated_at DESC",
        "label": "Fila de pedidos por status",
    },
    {
        "name": "ix_installments_open_due",
        "ddl": "CREATE INDEX ix_installments_open_due ON receivable_installments (due_date) WHERE amount > principal_paid + discount_granted",
        "query": "SELECT i.id, t.id, n.invoice_number, c.name, i.due_date, i.amount FROM receivable_installments i "
                 "JOIN receivable_titles t ON t.id = i.title_id JOIN invoices n ON n.id = t.invoice_id JOIN customers c ON c.id = t.customer_id "
                 "WHERE t.status <> 'CANCELLED' AND i.amount > i.principal_paid + i.discount_granted AND i.due_date < CURRENT_DATE "
                 "ORDER BY i.due_date, i.id",
        "label": "Títulos vencidos",
    },
    {
        "name": "ix_outbox_pending",
        "ddl": "CREATE INDEX ix_outbox_pending ON outbox_events (id) WHERE status = 'PENDING'",
        "query": "SELECT FIRST 20 id, event_type, payload, idempotency_key, attempts FROM outbox_events "
                 "WHERE status = 'PENDING' AND next_attempt_at <= LOCALTIMESTAMP AND (claimed_until IS NULL OR claimed_until < LOCALTIMESTAMP) "
                 "ORDER BY id WITH LOCK SKIP LOCKED",
        "label": "Worker pegando eventos da outbox",
    },
    {
        "name": "ix_audit_entity",
        "ddl": "CREATE INDEX ix_audit_entity ON audit_events (entity_type, entity_id)",
        "query": "SELECT FIRST 500 a.occurred_at, a.action, u.username FROM audit_events a LEFT JOIN users u ON u.id = a.user_id "
                 "WHERE a.entity_type = 'product' AND a.entity_id = 1234 ORDER BY a.id DESC",
        "label": "Histórico de uma entidade",
    },
    {
        # Controle: busca com curinga a esquerda nao usa indice. Medido para nao criar indice inutil.
        "name": "ix_products_name_upper",
        "ddl": "CREATE INDEX ix_products_name_upper ON products COMPUTED BY (UPPER(name))",
        "query": "SELECT FIRST 500 id, sku, name FROM products WHERE UPPER(sku) LIKE '%007%' OR UPPER(name) LIKE '%007%' ORDER BY sku",
        "label": "Busca de produto por trecho do nome",
    },
]


def isql(script):
    done = subprocess.run([ISQL, "-q", "-user", USER, "-password", PASSWORD, DSN], input=script,
                          capture_output=True, text=True)
    return done.stdout + done.stderr


def ddl(statement):
    return isql(statement + ";\nCOMMIT;\n")


def drop_if_exists(name):
    ddl(f"DROP INDEX {name}")


def measure(query):
    elapsed, fetches, reads, plan = [], None, None, ""
    for _ in range(RUNS):
        output = isql(f"SET PLAN ON;\nSET STATS ON;\nSET HEADING OFF;\nSET LIST OFF;\n{query};\nROLLBACK;\n")
        time_match = re.search(r"Elapsed time\s*=\s*([\d.]+)\s*sec", output)
        fetch_match = re.search(r"Fetches\s*=\s*(\d+)", output)
        read_match = re.search(r"Reads\s*=\s*(\d+)", output)
        plans = re.findall(r"^PLAN .*$", output, re.M)
        if not time_match or not fetch_match:
            raise SystemExit(f"Saida inesperada do isql:\n{output[-1500:]}")
        elapsed.append(float(time_match.group(1)) * 1000)
        fetches = int(fetch_match.group(1))
        reads = int(read_match.group(1))
        plan = plans[-1] if plans else ""
    return statistics.median(elapsed), fetches, reads, plan


print("| Consulta | Índice candidato | Tempo sem (ms) | Tempo com (ms) | Fetches sem | Fetches com | Índice usado? |")
print("|---|---|---:|---:|---:|---:|---|")
details = []
for candidate in CANDIDATES:
    drop_if_exists(candidate["name"])
    # Aquece o cache para comparar custo de CPU, nao de disco frio.
    measure(candidate["query"])
    without = measure(candidate["query"])
    ddl(candidate["ddl"])
    measure(candidate["query"])
    with_index = measure(candidate["query"])
    used = "sim" if candidate["name"].upper() in with_index[3].upper() else "não"
    print(f"| {candidate['label']} | `{candidate['name']}` | {without[0]:.0f} | {with_index[0]:.0f} | {without[1]} | {with_index[1]} | {used} |")
    details.append((candidate, without[3], with_index[3]))
    drop_if_exists(candidate["name"])

print()
for candidate, before, after in details:
    print(f"**{candidate['label']}**\n\n```text\nsem: {before}\ncom: {after}\n```\n")
