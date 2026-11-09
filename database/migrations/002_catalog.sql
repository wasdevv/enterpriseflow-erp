-- Cadastros. Precos e limites ficam aqui; historico de alteracao vai para audit_events.
CREATE SEQUENCE seq_categories;
CREATE TABLE categories (
  id BIGINT NOT NULL PRIMARY KEY,
  name VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE units (
  code VARCHAR(6) NOT NULL PRIMARY KEY,
  name VARCHAR(40) NOT NULL,
  allows_fraction d_flag
);

CREATE SEQUENCE seq_products;
CREATE TABLE products (
  id BIGINT NOT NULL PRIMARY KEY,
  sku VARCHAR(30) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  category_id BIGINT REFERENCES categories (id),
  unit_code VARCHAR(6) NOT NULL REFERENCES units (code),
  sale_price d_money,
  minimum_stock d_qty,
  is_active d_flag,
  updated_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  CONSTRAINT ck_products_price CHECK (sale_price >= 0),
  CONSTRAINT ck_products_minimum CHECK (minimum_stock >= 0)
);

CREATE SEQUENCE seq_customers;
CREATE TABLE customers (
  id BIGINT NOT NULL PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  document VARCHAR(14) NOT NULL UNIQUE,
  email VARCHAR(120),
  phone VARCHAR(20),
  credit_limit d_money,
  is_active d_flag,
  updated_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL,
  CONSTRAINT ck_customers_limit CHECK (credit_limit >= 0)
);

CREATE SEQUENCE seq_suppliers;
CREATE TABLE suppliers (
  id BIGINT NOT NULL PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  document VARCHAR(14) NOT NULL UNIQUE,
  email VARCHAR(120),
  phone VARCHAR(20),
  is_active d_flag
);

CREATE SEQUENCE seq_carriers;
CREATE TABLE carriers (
  id BIGINT NOT NULL PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  document VARCHAR(14) NOT NULL UNIQUE,
  phone VARCHAR(20),
  is_active d_flag
);

CREATE SEQUENCE seq_warehouses;
CREATE TABLE warehouses (
  id BIGINT NOT NULL PRIMARY KEY,
  code VARCHAR(10) NOT NULL UNIQUE,
  name VARCHAR(60) NOT NULL,
  is_active d_flag
);

CREATE SEQUENCE seq_storage_locations;
CREATE TABLE storage_locations (
  id BIGINT NOT NULL PRIMARY KEY,
  warehouse_id BIGINT NOT NULL REFERENCES warehouses (id),
  code VARCHAR(20) NOT NULL,
  description VARCHAR(80),
  CONSTRAINT uq_storage_locations UNIQUE (warehouse_id, code)
);
