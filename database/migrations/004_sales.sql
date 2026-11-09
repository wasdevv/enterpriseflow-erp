CREATE SEQUENCE seq_sales_orders;
CREATE TABLE sales_orders (
  id BIGINT NOT NULL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customers (id),
  seller_id BIGINT NOT NULL REFERENCES users (id),
  carrier_id BIGINT REFERENCES carriers (id),
  status VARCHAR(10) NOT NULL,
  -- UNIQUE: repetir a confirmacao com a mesma chave nao cria outro pedido.
  -- Pode ser nula em rascunho; varios NULL sao permitidos.
  idempotency_key VARCHAR(64) UNIQUE,
  total d_money,
  installments INTEGER DEFAULT 1 NOT NULL,
  installment_interval_days INTEGER DEFAULT 30 NOT NULL,
  cancel_reason VARCHAR(200),
  created_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  updated_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  CONSTRAINT ck_order_status CHECK (status IN
    ('DRAFT', 'CONFIRMED', 'RESERVED', 'PICKING', 'SHIPPED', 'INVOICED', 'CANCELLED')),
  CONSTRAINT ck_order_total CHECK (total >= 0),
  CONSTRAINT ck_order_installments CHECK (installments BETWEEN 1 AND 48),
  CONSTRAINT ck_order_interval CHECK (installment_interval_days BETWEEN 1 AND 180)
);

-- Defesa em profundidade: o servico de dominio valida a maquina de estados inteira;
-- aqui so garantimos que nem SQL direto tira um pedido de um estado terminal.
SET TERM ^ ;
CREATE TRIGGER trg_sales_orders_terminal FOR sales_orders
ACTIVE BEFORE UPDATE POSITION 0
AS
BEGIN
  IF (OLD.status IN ('INVOICED', 'CANCELLED') AND NEW.status <> OLD.status) THEN
    EXCEPTION ex_terminal_status;
END^
SET TERM ; ^

CREATE SEQUENCE seq_sales_order_items;
CREATE TABLE sales_order_items (
  id BIGINT NOT NULL PRIMARY KEY,
  sales_order_id BIGINT NOT NULL REFERENCES sales_orders (id),
  product_id BIGINT NOT NULL REFERENCES products (id),
  warehouse_id BIGINT NOT NULL REFERENCES warehouses (id),
  quantity d_qty,
  unit_price d_money,
  line_total d_money,
  CONSTRAINT uq_order_item UNIQUE (sales_order_id, product_id, warehouse_id),
  CONSTRAINT ck_order_item_quantity CHECK (quantity > 0),
  CONSTRAINT ck_order_item_price CHECK (unit_price >= 0)
);

CREATE SEQUENCE seq_order_status_history;
CREATE TABLE sales_order_status_history (
  id BIGINT NOT NULL PRIMARY KEY,
  sales_order_id BIGINT NOT NULL REFERENCES sales_orders (id),
  from_status VARCHAR(10),
  to_status VARCHAR(10) NOT NULL,
  user_id BIGINT NOT NULL REFERENCES users (id),
  reason VARCHAR(200),
  occurred_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL
);

SET TERM ^ ;
CREATE TRIGGER trg_order_history_immutable FOR sales_order_status_history
ACTIVE BEFORE UPDATE OR DELETE POSITION 0
AS
BEGIN
  EXCEPTION ex_append_only;
END^
SET TERM ; ^

-- UNIQUE em sales_order_item_id: um item tem no maximo uma reserva na vida.
CREATE SEQUENCE seq_stock_reservations;
CREATE TABLE stock_reservations (
  id BIGINT NOT NULL PRIMARY KEY,
  sales_order_id BIGINT NOT NULL REFERENCES sales_orders (id),
  sales_order_item_id BIGINT NOT NULL UNIQUE REFERENCES sales_order_items (id),
  product_id BIGINT NOT NULL REFERENCES products (id),
  warehouse_id BIGINT NOT NULL REFERENCES warehouses (id),
  quantity d_qty,
  status VARCHAR(10) DEFAULT 'ACTIVE' NOT NULL,
  created_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  closed_at TIMESTAMP,
  CONSTRAINT ck_reservation_status CHECK (status IN ('ACTIVE', 'RELEASED', 'CONSUMED')),
  CONSTRAINT ck_reservation_quantity CHECK (quantity > 0)
);

SET TERM ^ ;
CREATE TRIGGER trg_reservations_closed FOR stock_reservations
ACTIVE BEFORE UPDATE POSITION 0
AS
BEGIN
  IF (OLD.status <> 'ACTIVE') THEN
    EXCEPTION ex_reservation_closed;
END^
SET TERM ; ^
