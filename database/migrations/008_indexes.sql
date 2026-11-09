-- So os indices que se pagaram na medicao de docs/performance.md (scripts/measure-indexes.py).
-- Rejeitados: composto do Kardex (as FKs ja atendem, e a tabela tem muita escrita) e busca por
-- trecho de nome (curinga a esquerda nao usa indice).
CREATE DESCENDING INDEX ix_orders_queue ON sales_orders (status, updated_at);
CREATE INDEX ix_audit_entity ON audit_events (entity_type, entity_id);

-- Parciais (Firebird 5): indexam so as poucas linhas que interessam. Pago e enviado, que sao
-- quase tudo depois de um ano de operacao, nao entram no indice.
CREATE INDEX ix_installments_open_due ON receivable_installments (due_date) WHERE amount > principal_paid + discount_granted;
CREATE INDEX ix_outbox_pending ON outbox_events (id) WHERE status = 'PENDING';
