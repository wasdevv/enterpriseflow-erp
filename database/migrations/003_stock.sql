-- Estoque. As CHECKs sao a ultima linha de defesa: mesmo um bug no servico de
-- aplicacao nao consegue gravar saldo negativo nem reservar acima do fisico.
CREATE TABLE stock_balances (
  product_id BIGINT NOT NULL REFERENCES products (id),
  warehouse_id BIGINT NOT NULL REFERENCES warehouses (id),
  location_id BIGINT REFERENCES storage_locations (id),
  on_hand d_qty,
  reserved d_qty,
  updated_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  PRIMARY KEY (product_id, warehouse_id),
  CONSTRAINT ck_balance_on_hand CHECK (on_hand >= 0),
  CONSTRAINT ck_balance_reserved CHECK (reserved >= 0),
  CONSTRAINT ck_balance_reserved_on_hand CHECK (reserved <= on_hand)
);

-- Kardex: on_hand_delta/reserved_delta permitem reconciliar o saldo somando movimentos.
CREATE SEQUENCE seq_stock_movements;
CREATE TABLE stock_movements (
  id BIGINT NOT NULL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products (id),
  warehouse_id BIGINT NOT NULL REFERENCES warehouses (id),
  movement_type VARCHAR(16) NOT NULL,
  quantity d_qty,
  on_hand_delta d_qty,
  reserved_delta d_qty,
  on_hand_after d_qty,
  reserved_after d_qty,
  reason VARCHAR(200) NOT NULL,
  user_id BIGINT NOT NULL REFERENCES users (id),
  source_type VARCHAR(24) NOT NULL,
  source_id BIGINT NOT NULL,
  correlation_id VARCHAR(36),
  occurred_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  CONSTRAINT ck_movement_type CHECK (movement_type IN
    ('ENTRY', 'RESERVE', 'RELEASE', 'ISSUE', 'TRANSFER_OUT', 'TRANSFER_IN', 'ADJUSTMENT')),
  CONSTRAINT ck_movement_quantity CHECK (quantity > 0),
  CONSTRAINT ck_movement_reason CHECK (TRIM(reason) <> '')
);

SET TERM ^ ;
CREATE TRIGGER trg_stock_movements_immutable FOR stock_movements
ACTIVE BEFORE UPDATE OR DELETE POSITION 0
AS
BEGIN
  EXCEPTION ex_append_only;
END^
SET TERM ; ^

CREATE SEQUENCE seq_stock_transfers;
CREATE TABLE stock_transfers (
  id BIGINT NOT NULL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products (id),
  from_warehouse_id BIGINT NOT NULL REFERENCES warehouses (id),
  to_warehouse_id BIGINT NOT NULL REFERENCES warehouses (id),
  quantity d_qty,
  reason VARCHAR(200) NOT NULL,
  user_id BIGINT NOT NULL REFERENCES users (id),
  created_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  CONSTRAINT ck_transfer_warehouses CHECK (from_warehouse_id <> to_warehouse_id),
  CONSTRAINT ck_transfer_quantity CHECK (quantity > 0)
);

-- Ajuste de inventario so vale apos aprovacao de outra pessoa.
CREATE SEQUENCE seq_stock_adjustments;
CREATE TABLE stock_adjustments (
  id BIGINT NOT NULL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products (id),
  warehouse_id BIGINT NOT NULL REFERENCES warehouses (id),
  counted_quantity d_qty,
  reason VARCHAR(200) NOT NULL,
  status VARCHAR(10) DEFAULT 'PENDING' NOT NULL,
  requested_by BIGINT NOT NULL REFERENCES users (id),
  requested_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  decided_by BIGINT REFERENCES users (id),
  decided_at TIMESTAMP,
  CONSTRAINT ck_adjustment_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
  CONSTRAINT ck_adjustment_counted CHECK (counted_quantity >= 0),
  CONSTRAINT ck_adjustment_reason CHECK (TRIM(reason) <> ''),
  CONSTRAINT ck_adjustment_segregation CHECK (decided_by IS NULL OR decided_by <> requested_by)
);

CREATE SEQUENCE seq_purchase_orders;
CREATE TABLE purchase_orders (
  id BIGINT NOT NULL PRIMARY KEY,
  supplier_id BIGINT NOT NULL REFERENCES suppliers (id),
  warehouse_id BIGINT NOT NULL REFERENCES warehouses (id),
  status VARCHAR(20) DEFAULT 'OPEN' NOT NULL,
  note VARCHAR(200),
  created_by BIGINT NOT NULL REFERENCES users (id),
  created_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  CONSTRAINT ck_purchase_status CHECK (status IN ('OPEN', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED_SHORT'))
);

CREATE SEQUENCE seq_purchase_order_items;
CREATE TABLE purchase_order_items (
  id BIGINT NOT NULL PRIMARY KEY,
  purchase_order_id BIGINT NOT NULL REFERENCES purchase_orders (id),
  product_id BIGINT NOT NULL REFERENCES products (id),
  quantity_ordered d_qty,
  quantity_received d_qty,
  unit_cost d_money,
  CONSTRAINT uq_purchase_item UNIQUE (purchase_order_id, product_id),
  CONSTRAINT ck_purchase_item_ordered CHECK (quantity_ordered > 0),
  CONSTRAINT ck_purchase_item_received CHECK (quantity_received >= 0)
);

CREATE SEQUENCE seq_purchase_receipts;
CREATE TABLE purchase_receipts (
  id BIGINT NOT NULL PRIMARY KEY,
  purchase_order_id BIGINT NOT NULL REFERENCES purchase_orders (id),
  idempotency_key VARCHAR(64) NOT NULL UNIQUE,
  received_by BIGINT NOT NULL REFERENCES users (id),
  received_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  note VARCHAR(200)
);

-- outstanding_before guarda o que faltava no momento da conferencia; divergence e a
-- diferenca em relacao a esse saldo (positiva = veio a mais, negativa = veio a menos).
CREATE SEQUENCE seq_purchase_receipt_items;
CREATE TABLE purchase_receipt_items (
  id BIGINT NOT NULL PRIMARY KEY,
  receipt_id BIGINT NOT NULL REFERENCES purchase_receipts (id),
  purchase_order_item_id BIGINT NOT NULL REFERENCES purchase_order_items (id),
  quantity_received d_qty,
  outstanding_before d_qty,
  divergence d_qty,
  divergence_note VARCHAR(200),
  CONSTRAINT ck_receipt_item_quantity CHECK (quantity_received > 0)
);
