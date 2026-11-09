-- Tipos, excecoes e controle de acesso.
-- Dinheiro e quantidade sao NUMERIC (inteiro escalado): nunca ponto flutuante.
CREATE DOMAIN d_money AS NUMERIC(18,2) DEFAULT 0 NOT NULL;
CREATE DOMAIN d_qty AS NUMERIC(15,3) DEFAULT 0 NOT NULL;
CREATE DOMAIN d_flag AS BOOLEAN DEFAULT TRUE NOT NULL;

CREATE EXCEPTION ex_append_only 'Registro imutavel: tabela aceita apenas INSERT';
CREATE EXCEPTION ex_terminal_status 'Status terminal nao pode ser alterado';
CREATE EXCEPTION ex_reservation_closed 'Reserva encerrada nao pode ser alterada';

CREATE SEQUENCE seq_users;
CREATE TABLE users (
  id BIGINT NOT NULL PRIMARY KEY,
  username VARCHAR(40) NOT NULL UNIQUE,
  full_name VARCHAR(120) NOT NULL,
  password_hash VARCHAR(64) NOT NULL,
  password_salt VARCHAR(64) NOT NULL,
  password_iterations INTEGER NOT NULL,
  is_active d_flag,
  failed_attempts INTEGER DEFAULT 0 NOT NULL,
  locked_until TIMESTAMP,
  created_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL
);

CREATE SEQUENCE seq_roles;
CREATE TABLE roles (
  id BIGINT NOT NULL PRIMARY KEY,
  code VARCHAR(30) NOT NULL UNIQUE,
  name VARCHAR(60) NOT NULL
);

CREATE TABLE user_roles (
  user_id BIGINT NOT NULL REFERENCES users (id),
  role_id BIGINT NOT NULL REFERENCES roles (id),
  PRIMARY KEY (user_id, role_id)
);

CREATE TABLE role_permissions (
  role_id BIGINT NOT NULL REFERENCES roles (id),
  permission_code VARCHAR(40) NOT NULL,
  PRIMARY KEY (role_id, permission_code)
);

CREATE TABLE settings (
  setting_key VARCHAR(60) NOT NULL PRIMARY KEY,
  setting_value VARCHAR(200) NOT NULL
);
