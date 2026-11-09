-- Dados de referencia: sem eles o sistema nao funciona, por isso sao migration e nao seed.
-- TRIM nas permissoes: UNION de literais vira CHAR, e o codigo curto chegaria com espacos a
-- direita. A comparacao no banco ignora esses espacos, mas a do aplicativo nao.
INSERT INTO units (code, name, allows_fraction) VALUES ('UN', 'Unidade', FALSE);
INSERT INTO units (code, name, allows_fraction) VALUES ('M', 'Metro', TRUE);
INSERT INTO units (code, name, allows_fraction) VALUES ('RL', 'Rolo', FALSE);
INSERT INTO units (code, name, allows_fraction) VALUES ('CX', 'Caixa', FALSE);

INSERT INTO settings (setting_key, setting_value) VALUES ('credit_check_enabled', '1');
INSERT INTO settings (setting_key, setting_value) VALUES ('late_penalty_bps', '200');
INSERT INTO settings (setting_key, setting_value) VALUES ('late_interest_monthly_bps', '100');

INSERT INTO roles (id, code, name) VALUES (NEXT VALUE FOR seq_roles, 'ADMIN', 'Administrador');
INSERT INTO roles (id, code, name) VALUES (NEXT VALUE FOR seq_roles, 'VENDAS', 'Vendas');
INSERT INTO roles (id, code, name) VALUES (NEXT VALUE FOR seq_roles, 'ESTOQUE', 'Estoque');
INSERT INTO roles (id, code, name) VALUES (NEXT VALUE FOR seq_roles, 'FINANCEIRO', 'Financeiro');
INSERT INTO roles (id, code, name) VALUES (NEXT VALUE FOR seq_roles, 'GERENTE', 'Gerente');

INSERT INTO role_permissions (role_id, permission_code)
  SELECT r.id, TRIM(p.code) FROM roles r CROSS JOIN (
    SELECT 'catalog.manage' AS code FROM RDB$DATABASE
    UNION ALL SELECT 'users.manage' FROM RDB$DATABASE
    UNION ALL SELECT 'stock.move' FROM RDB$DATABASE
    UNION ALL SELECT 'stock.adjust.request' FROM RDB$DATABASE
    UNION ALL SELECT 'stock.adjust.approve' FROM RDB$DATABASE
    UNION ALL SELECT 'purchase.manage' FROM RDB$DATABASE
    UNION ALL SELECT 'order.create' FROM RDB$DATABASE
    UNION ALL SELECT 'order.confirm' FROM RDB$DATABASE
    UNION ALL SELECT 'order.cancel' FROM RDB$DATABASE
    UNION ALL SELECT 'order.fulfill' FROM RDB$DATABASE
    UNION ALL SELECT 'invoice.create' FROM RDB$DATABASE
    UNION ALL SELECT 'receivable.settle' FROM RDB$DATABASE
    UNION ALL SELECT 'receivable.reverse' FROM RDB$DATABASE
    UNION ALL SELECT 'reports.view' FROM RDB$DATABASE
    UNION ALL SELECT 'integration.manage' FROM RDB$DATABASE
  ) p WHERE r.code = 'ADMIN';

INSERT INTO role_permissions (role_id, permission_code)
  SELECT r.id, TRIM(p.code) FROM roles r CROSS JOIN (
    SELECT 'order.create' AS code FROM RDB$DATABASE
    UNION ALL SELECT 'order.confirm' FROM RDB$DATABASE
    UNION ALL SELECT 'order.cancel' FROM RDB$DATABASE
    UNION ALL SELECT 'reports.view' FROM RDB$DATABASE
  ) p WHERE r.code = 'VENDAS';

INSERT INTO role_permissions (role_id, permission_code)
  SELECT r.id, TRIM(p.code) FROM roles r CROSS JOIN (
    SELECT 'stock.move' AS code FROM RDB$DATABASE
    UNION ALL SELECT 'stock.adjust.request' FROM RDB$DATABASE
    UNION ALL SELECT 'purchase.manage' FROM RDB$DATABASE
    UNION ALL SELECT 'order.fulfill' FROM RDB$DATABASE
    UNION ALL SELECT 'reports.view' FROM RDB$DATABASE
  ) p WHERE r.code = 'ESTOQUE';

INSERT INTO role_permissions (role_id, permission_code)
  SELECT r.id, TRIM(p.code) FROM roles r CROSS JOIN (
    SELECT 'invoice.create' AS code FROM RDB$DATABASE
    UNION ALL SELECT 'receivable.settle' FROM RDB$DATABASE
    UNION ALL SELECT 'receivable.reverse' FROM RDB$DATABASE
    UNION ALL SELECT 'reports.view' FROM RDB$DATABASE
  ) p WHERE r.code = 'FINANCEIRO';

INSERT INTO role_permissions (role_id, permission_code)
  SELECT r.id, TRIM(p.code) FROM roles r CROSS JOIN (
    SELECT 'stock.adjust.approve' AS code FROM RDB$DATABASE
    UNION ALL SELECT 'catalog.manage' FROM RDB$DATABASE
    UNION ALL SELECT 'reports.view' FROM RDB$DATABASE
  ) p WHERE r.code = 'GERENTE';
