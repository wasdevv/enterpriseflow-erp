CREATE SEQUENCE seq_invoices;
CREATE SEQUENCE seq_invoice_number;
CREATE TABLE invoices (
  id BIGINT NOT NULL PRIMARY KEY,
  invoice_number BIGINT NOT NULL UNIQUE,
  -- UNIQUE: um pedido fatura no maximo uma vez.
  sales_order_id BIGINT NOT NULL UNIQUE REFERENCES sales_orders (id),
  customer_id BIGINT NOT NULL REFERENCES customers (id),
  total d_money,
  issued_by BIGINT NOT NULL REFERENCES users (id),
  issued_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL
);

CREATE SEQUENCE seq_receivable_titles;
CREATE TABLE receivable_titles (
  id BIGINT NOT NULL PRIMARY KEY,
  invoice_id BIGINT NOT NULL UNIQUE REFERENCES invoices (id),
  customer_id BIGINT NOT NULL REFERENCES customers (id),
  total d_money,
  -- Atraso e condicao derivada de due_date (ADR 003), nao um status persistido.
  status VARCHAR(16) DEFAULT 'OPEN' NOT NULL,
  created_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  CONSTRAINT ck_title_status CHECK (status IN ('OPEN', 'PARTIALLY_PAID', 'PAID', 'CANCELLED'))
);

CREATE SEQUENCE seq_receivable_installments;
CREATE TABLE receivable_installments (
  id BIGINT NOT NULL PRIMARY KEY,
  title_id BIGINT NOT NULL REFERENCES receivable_titles (id),
  installment_no INTEGER NOT NULL,
  due_date DATE NOT NULL,
  amount d_money,
  principal_paid d_money,
  discount_granted d_money,
  CONSTRAINT uq_installment UNIQUE (title_id, installment_no),
  CONSTRAINT ck_installment_amount CHECK (amount > 0),
  CONSTRAINT ck_installment_paid CHECK (principal_paid >= 0 AND discount_granted >= 0),
  CONSTRAINT ck_installment_overpaid CHECK (principal_paid + discount_granted <= amount)
);

-- Estorno = nova linha com valores negados e reversal_of_id apontando a original.
-- UNIQUE em reversal_of_id: uma liquidacao so pode ser estornada uma vez.
CREATE SEQUENCE seq_receivable_settlements;
CREATE TABLE receivable_settlements (
  id BIGINT NOT NULL PRIMARY KEY,
  installment_id BIGINT NOT NULL REFERENCES receivable_installments (id),
  principal d_money,
  interest d_money,
  penalty d_money,
  discount d_money,
  paid_on DATE NOT NULL,
  user_id BIGINT NOT NULL REFERENCES users (id),
  idempotency_key VARCHAR(64) NOT NULL UNIQUE,
  reversal_of_id BIGINT UNIQUE REFERENCES receivable_settlements (id),
  note VARCHAR(200),
  created_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  CONSTRAINT ck_settlement_sign CHECK (
    (reversal_of_id IS NULL AND principal >= 0 AND interest >= 0 AND penalty >= 0 AND discount >= 0)
    OR
    (reversal_of_id IS NOT NULL AND principal <= 0 AND interest <= 0 AND penalty <= 0 AND discount <= 0)
  )
);

SET TERM ^ ;
CREATE TRIGGER trg_settlements_immutable FOR receivable_settlements
ACTIVE BEFORE UPDATE OR DELETE POSITION 0
AS
BEGIN
  EXCEPTION ex_append_only;
END^
SET TERM ; ^
