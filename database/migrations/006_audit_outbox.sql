CREATE SEQUENCE seq_audit_events;
CREATE TABLE audit_events (
  id BIGINT NOT NULL PRIMARY KEY,
  occurred_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  user_id BIGINT REFERENCES users (id),
  action VARCHAR(40) NOT NULL,
  entity_type VARCHAR(30) NOT NULL,
  entity_id BIGINT NOT NULL,
  correlation_id VARCHAR(36),
  details BLOB SUB_TYPE TEXT CHARACTER SET UTF8
);

SET TERM ^ ;
CREATE TRIGGER trg_audit_immutable FOR audit_events
ACTIVE BEFORE UPDATE OR DELETE POSITION 0
AS
BEGIN
  EXCEPTION ex_append_only;
END^
SET TERM ; ^

-- A outbox grava o evento na mesma transacao do negocio; o worker publica depois do
-- commit. idempotency_key e o que torna a entrega "pelo menos uma vez" segura.
CREATE SEQUENCE seq_outbox_events;
CREATE TABLE outbox_events (
  id BIGINT NOT NULL PRIMARY KEY,
  event_type VARCHAR(40) NOT NULL,
  aggregate_type VARCHAR(30) NOT NULL,
  aggregate_id BIGINT NOT NULL,
  payload BLOB SUB_TYPE TEXT CHARACTER SET UTF8 NOT NULL,
  idempotency_key VARCHAR(64) NOT NULL UNIQUE,
  correlation_id VARCHAR(36),
  status VARCHAR(10) DEFAULT 'PENDING' NOT NULL,
  attempts INTEGER DEFAULT 0 NOT NULL,
  next_attempt_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  claimed_until TIMESTAMP,
  last_error VARCHAR(500),
  created_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  sent_at TIMESTAMP,
  CONSTRAINT ck_outbox_status CHECK (status IN ('PENDING', 'SENT', 'DEAD'))
);

-- Nunca guardar segredo aqui: cabecalhos de autenticacao nao sao gravados.
CREATE SEQUENCE seq_integration_logs;
CREATE TABLE integration_logs (
  id BIGINT NOT NULL PRIMARY KEY,
  occurred_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  correlation_id VARCHAR(36),
  idempotency_key VARCHAR(64),
  http_method VARCHAR(8) NOT NULL,
  url VARCHAR(300) NOT NULL,
  attempt INTEGER NOT NULL,
  http_status INTEGER,
  duration_ms INTEGER NOT NULL,
  outcome VARCHAR(20) NOT NULL,
  error_message VARCHAR(500),
  response_excerpt VARCHAR(500)
);

-- Pedido recusado da rollback em tudo: a recusa so sobrevive se for gravada em
-- transacao propria, por isso a metrica mora fora do fluxo de negocio.
CREATE SEQUENCE seq_metric_events;
CREATE TABLE metric_events (
  id BIGINT NOT NULL PRIMARY KEY,
  metric VARCHAR(40) NOT NULL,
  correlation_id VARCHAR(36),
  detail VARCHAR(200),
  duration_ms INTEGER,
  occurred_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL
);
