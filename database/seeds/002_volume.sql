-- Volume sintético para medição de índices, proporcional ao cenário fictício: 8.000 SKUs,
-- 2 depósitos, 12 meses a 1.500 pedidos/mês e 400 movimentos/dia. Rode sobre 001_demo.sql.
-- Não representa operação real: serve só para comparar planos antes e depois de cada índice.
SET TERM ^ ;

EXECUTE BLOCK AS
  DECLARE i INTEGER = 1;
  DECLARE category_id BIGINT;
  DECLARE product_id BIGINT;
BEGIN
  SELECT MIN(id) FROM categories INTO :category_id;
  WHILE (i <= 8000) DO
  BEGIN
    product_id = NEXT VALUE FOR seq_products;
    INSERT INTO products (id, sku, name, category_id, unit_code, sale_price, minimum_stock)
    VALUES (:product_id, 'VOL-' || LPAD(:i, 6, '0'), 'Item sintético ' || :i, :category_id, 'UN', 10 + MOD(:i, 90), 5);
    INSERT INTO stock_balances (product_id, warehouse_id, on_hand, reserved)
      SELECT :product_id, id, 1000, 0 FROM warehouses;
    i = i + 1;
  END
END^

EXECUTE BLOCK AS
  DECLARE i INTEGER = 1;
  DECLARE first_product BIGINT;
  DECLARE warehouse_a BIGINT;
  DECLARE warehouse_b BIGINT;
  DECLARE user_id BIGINT;
  DECLARE occurred TIMESTAMP;
BEGIN
  SELECT MIN(id) FROM products WHERE sku STARTING WITH 'VOL-' INTO :first_product;
  SELECT MIN(id), MAX(id) FROM warehouses INTO :warehouse_a, :warehouse_b;
  SELECT id FROM users WHERE username = 'admin' INTO :user_id;
  occurred = DATEADD(-365 DAY TO LOCALTIMESTAMP);
  WHILE (i <= 146000) DO
  BEGIN
    INSERT INTO stock_movements (id, product_id, warehouse_id, movement_type, quantity, on_hand_delta, reserved_delta,
      on_hand_after, reserved_after, reason, user_id, source_type, source_id, occurred_at)
    VALUES (NEXT VALUE FOR seq_stock_movements, :first_product + MOD(:i * 7, 8000),
      IIF(MOD(:i, 2) = 0, :warehouse_a, :warehouse_b), 'ENTRY', 1, 0, 0, 1000, 0, 'Volume sintético', :user_id, 'SEED', :i,
      DATEADD(:i * 216 SECOND TO :occurred));
    i = i + 1;
  END
END^

EXECUTE BLOCK AS
  DECLARE i INTEGER = 1;
  DECLARE customer_count INTEGER;
  DECLARE first_customer BIGINT;
  DECLARE user_id BIGINT;
  DECLARE order_id BIGINT;
  DECLARE invoice_id BIGINT;
  DECLARE title_id BIGINT;
  DECLARE status_code VARCHAR(10);
  DECLARE created TIMESTAMP;
  DECLARE due DATE;
BEGIN
  SELECT MIN(id), COUNT(*) FROM customers INTO :first_customer, :customer_count;
  SELECT id FROM users WHERE username = 'admin' INTO :user_id;
  WHILE (i <= 18000) DO
  BEGIN
    /* A maioria ja faturada; fracao pequena segue na fila operacional. */
    status_code = IIF(MOD(:i, 50) = 0, 'RESERVED', IIF(MOD(:i, 50) = 1, 'PICKING', IIF(MOD(:i, 50) = 2, 'SHIPPED', IIF(MOD(:i, 25) = 7, 'CANCELLED', 'INVOICED'))));
    created = DATEADD(:i * 1752 SECOND TO DATEADD(-365 DAY TO LOCALTIMESTAMP));
    order_id = NEXT VALUE FOR seq_sales_orders;
    INSERT INTO sales_orders (id, customer_id, seller_id, status, total, created_at, updated_at)
    VALUES (:order_id, :first_customer + MOD(:i, :customer_count), :user_id, :status_code, 100, :created, :created);
    IF (status_code = 'INVOICED') THEN
    BEGIN
      invoice_id = NEXT VALUE FOR seq_invoices;
      INSERT INTO invoices (id, invoice_number, sales_order_id, customer_id, total, issued_by, issued_at)
      VALUES (:invoice_id, NEXT VALUE FOR seq_invoice_number, :order_id, :first_customer + MOD(:i, :customer_count), 100, :user_id, :created);
      title_id = NEXT VALUE FOR seq_receivable_titles;
      INSERT INTO receivable_titles (id, invoice_id, customer_id, total, status)
      VALUES (:title_id, :invoice_id, :first_customer + MOD(:i, :customer_count), 100, IIF(MOD(:i, 20) = 3, 'OPEN', 'PAID'));
      due = CAST(DATEADD(30 DAY TO :created) AS DATE);
      INSERT INTO receivable_installments (id, title_id, installment_no, due_date, amount, principal_paid)
      VALUES (NEXT VALUE FOR seq_receivable_installments, :title_id, 1, :due, 50, IIF(MOD(:i, 20) = 3, 0, 50));
      INSERT INTO receivable_installments (id, title_id, installment_no, due_date, amount, principal_paid)
      VALUES (NEXT VALUE FOR seq_receivable_installments, :title_id, 2, DATEADD(30 DAY TO :due), 50, IIF(MOD(:i, 20) = 3, 0, 50));
      INSERT INTO outbox_events (id, event_type, aggregate_type, aggregate_id, payload, idempotency_key, status, attempts, sent_at, next_attempt_at)
      VALUES (NEXT VALUE FOR seq_outbox_events, 'invoice.issued', 'invoice', :invoice_id, '{}', 'vol-' || :invoice_id,
        IIF(MOD(:i, 500) = 3, 'PENDING', 'SENT'), 1, :created, :created);
    END
    INSERT INTO audit_events (id, user_id, action, entity_type, entity_id, occurred_at)
    VALUES (NEXT VALUE FOR seq_audit_events, :user_id, 'order.confirmed', 'sales_order', :order_id, :created);
    INSERT INTO audit_events (id, user_id, action, entity_type, entity_id, occurred_at)
    VALUES (NEXT VALUE FOR seq_audit_events, :user_id, 'product.updated', 'product', MOD(:i, 8000) + 1, :created);
    i = i + 1;
  END
END^

SET TERM ; ^
