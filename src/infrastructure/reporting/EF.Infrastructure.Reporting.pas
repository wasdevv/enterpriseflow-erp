unit EF.Infrastructure.Reporting;

{$I EF.inc}

interface

uses
  SysUtils, Classes,
  EF.Application.Ports, EF.Infrastructure.Database;

type
  TReadModel = class(TInterfacedObject, IReadModel)
  private
    FDb: IDbSession;
    function Run(const ASql: string): TDataTable; overload;
    function Run(const ASql: string; const AParams: array of TDbParam): TDataTable; overload;
  public
    constructor Create(const ADb: IDbSession);
    function Products(const ASearch: string): TDataTable;
    function Customers(const ASearch: string): TDataTable;
    function Parties(const AKind: TPartyKind): TDataTable;
    function Warehouses: TDataTable;
    function Locations(const AWarehouseId: Int64): TDataTable;
    function Categories: TDataTable;
    function Units: TDataTable;
    function StockBalances(const ASearch: string): TDataTable;
    function LowStock: TDataTable;
    function Kardex(const AProductId, AWarehouseId: Int64): TDataTable;
    function StockReconciliation: TDataTable;
    function PendingAdjustments: TDataTable;
    function SalesOrders(const AStatus: string): TDataTable;
    function SalesOrderItems(const AOrderId: Int64): TDataTable;
    function SalesOrderHistory(const AOrderId: Int64): TDataTable;
    function PurchaseOrders: TDataTable;
    function PurchaseOrderItems(const AOrderId: Int64): TDataTable;
    function PurchaseDivergences: TDataTable;
    function OpenInstallments(const AToday: TDateTime; const AOnlyOverdue: Boolean): TDataTable;
    function Settlements(const AInstallmentId: Int64): TDataTable;
    function CashFlow(const AFrom, ATo: TDateTime): TDataTable;
    function OutboxQueue: TDataTable;
    function IntegrationLog: TDataTable;
    function AuditTrail(const AEntityType: string; const AEntityId: Int64): TDataTable;
    function MetricsSummary: TDataTable;
  end;

{ CSV com ";" e BOM UTF-8: abre com acento correto no Excel em português. }
function DataTableToCsv(const ATable: TDataTable): TBytes;
procedure SaveDataTableCsv(const ATable: TDataTable; const APath: string);

implementation

function LikePattern(const ASearch: string): string;
begin
  Result := '%' + UpperCase(Trim(ASearch)) + '%';
end;

constructor TReadModel.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

function TReadModel.Run(const ASql: string): TDataTable;
var
  LNone: array of TDbParam;
begin
  LNone := nil;
  Result := Run(ASql, LNone);
end;

function TReadModel.Run(const ASql: string; const AParams: array of TDbParam): TDataTable;
var
  LReader: IDbReader;
  LColumn, LRow: Integer;
begin
  { Leitura curta em transação própria: tela aberta não segura transação no servidor. }
  FDb.StartTransaction;
  try
    LReader := FDb.Query(ASql, AParams);
    SetLength(Result.Columns, LReader.FieldCount);
    for LColumn := 0 to LReader.FieldCount - 1 do
      Result.Columns[LColumn] := LReader.FieldName(LColumn);
    LRow := 0;
    SetLength(Result.Rows, 0);
    while not LReader.Eof do
    begin
      SetLength(Result.Rows, LRow + 1);
      SetLength(Result.Rows[LRow], LReader.FieldCount);
      for LColumn := 0 to LReader.FieldCount - 1 do
        Result.Rows[LRow][LColumn] := LReader.DisplayText(LColumn);
      Inc(LRow);
      LReader.Next;
    end;
    LReader := nil;
    FDb.Commit;
  except
    FDb.Rollback;
    raise;
  end;
end;

function TReadModel.Products(const ASearch: string): TDataTable;
begin
  Result := Run(
    'SELECT FIRST 500 p.id AS ID, p.sku AS "SKU", p.name AS "Produto", c.name AS "Categoria", p.unit_code AS "Un", ' +
    'p.sale_price AS "Preço", p.minimum_stock AS "Mínimo", p.is_active AS "Ativo" ' +
    'FROM products p LEFT JOIN categories c ON c.id = p.category_id ' +
    'WHERE UPPER(p.sku) LIKE :pattern OR UPPER(p.name) LIKE :pattern ORDER BY p.sku',
    [P('pattern', LikePattern(ASearch))]);
end;

function TReadModel.Customers(const ASearch: string): TDataTable;
begin
  Result := Run(
    'SELECT FIRST 500 id AS ID, name AS "Cliente", document AS "CPF/CNPJ", email AS "E-mail", phone AS "Telefone", ' +
    'credit_limit AS "Limite de crédito", is_active AS "Ativo" FROM customers WHERE UPPER(name) LIKE :pattern OR document LIKE :pattern ORDER BY name',
    [P('pattern', LikePattern(ASearch))]);
end;

function TReadModel.Parties(const AKind: TPartyKind): TDataTable;
begin
  if AKind = pkSupplier then
    Result := Run('SELECT id AS ID, name AS "Fornecedor", document AS "CNPJ", email AS "E-mail", phone AS "Telefone", is_active AS "Ativo" FROM suppliers ORDER BY name')
  else
    Result := Run('SELECT id AS ID, name AS "Transportadora", document AS "CNPJ", phone AS "Telefone", is_active AS "Ativo" FROM carriers ORDER BY name');
end;

function TReadModel.Warehouses: TDataTable;
begin
  Result := Run('SELECT id AS ID, code AS "Código", name AS "Depósito", is_active AS "Ativo" FROM warehouses ORDER BY code');
end;

function TReadModel.Locations(const AWarehouseId: Int64): TDataTable;
begin
  Result := Run('SELECT id AS ID, code AS "Endereço", description AS "Descrição" FROM storage_locations WHERE warehouse_id = :warehouse_id ORDER BY code',
    [P('warehouse_id', AWarehouseId)]);
end;

function TReadModel.Categories: TDataTable;
begin
  Result := Run('SELECT id AS ID, name AS "Categoria" FROM categories ORDER BY name');
end;

function TReadModel.Units: TDataTable;
begin
  Result := Run('SELECT code AS "Código", name AS "Unidade", allows_fraction AS "Fracionável" FROM units ORDER BY code');
end;

function TReadModel.StockBalances(const ASearch: string): TDataTable;
begin
  Result := Run(
    'SELECT FIRST 500 p.id AS PRODUCT_ID, w.id AS WAREHOUSE_ID, p.sku AS "SKU", p.name AS "Produto", w.code AS "Depósito", ' +
    'b.on_hand AS "Físico", b.reserved AS "Reservado", CAST(b.on_hand - b.reserved AS NUMERIC(15,3)) AS "Disponível" ' +
    'FROM stock_balances b JOIN products p ON p.id = b.product_id JOIN warehouses w ON w.id = b.warehouse_id ' +
    'WHERE UPPER(p.sku) LIKE :pattern OR UPPER(p.name) LIKE :pattern ORDER BY p.sku, w.code',
    [P('pattern', LikePattern(ASearch))]);
end;

function TReadModel.LowStock: TDataTable;
begin
  Result := Run(
    'SELECT p.sku AS "SKU", p.name AS "Produto", p.minimum_stock AS "Mínimo", ' +
    'CAST(COALESCE(SUM(b.on_hand - b.reserved), 0) AS NUMERIC(15,3)) AS "Disponível" ' +
    'FROM products p LEFT JOIN stock_balances b ON b.product_id = p.id WHERE p.is_active ' +
    'GROUP BY p.sku, p.name, p.minimum_stock HAVING COALESCE(SUM(b.on_hand - b.reserved), 0) < p.minimum_stock ORDER BY p.sku');
end;

function TReadModel.Kardex(const AProductId, AWarehouseId: Int64): TDataTable;
begin
  Result := Run(
    'SELECT FIRST 1000 m.occurred_at AS "Data", m.movement_type AS "Tipo", m.quantity AS "Quantidade", m.on_hand_delta AS "Δ Físico", ' +
    'm.reserved_delta AS "Δ Reservado", m.on_hand_after AS "Físico após", m.reserved_after AS "Reservado após", ' +
    'm.reason AS "Motivo", u.username AS "Usuário", m.source_type AS "Documento", m.source_id AS "Nº" ' +
    'FROM stock_movements m JOIN users u ON u.id = m.user_id ' +
    'WHERE m.product_id = :product_id AND m.warehouse_id = :warehouse_id ORDER BY m.id DESC',
    [P('product_id', AProductId), P('warehouse_id', AWarehouseId)]);
end;

function TReadModel.StockReconciliation: TDataTable;
begin
  { Linha aqui significa divergência entre o saldo e a soma do Kardex: deveria ser vazio. }
  Result := Run(
    'SELECT p.sku AS "SKU", w.code AS "Depósito", b.on_hand AS "Saldo físico", ' +
    'CAST(COALESCE(k.on_hand_sum, 0) AS NUMERIC(15,3)) AS "Kardex físico", b.reserved AS "Saldo reservado", ' +
    'CAST(COALESCE(k.reserved_sum, 0) AS NUMERIC(15,3)) AS "Kardex reservado" ' +
    'FROM stock_balances b JOIN products p ON p.id = b.product_id JOIN warehouses w ON w.id = b.warehouse_id ' +
    'LEFT JOIN (SELECT product_id, warehouse_id, SUM(on_hand_delta) AS on_hand_sum, SUM(reserved_delta) AS reserved_sum ' +
    '           FROM stock_movements GROUP BY product_id, warehouse_id) k ' +
    'ON k.product_id = b.product_id AND k.warehouse_id = b.warehouse_id ' +
    'WHERE b.on_hand <> COALESCE(k.on_hand_sum, 0) OR b.reserved <> COALESCE(k.reserved_sum, 0) ORDER BY p.sku, w.code');
end;

function TReadModel.PendingAdjustments: TDataTable;
begin
  Result := Run(
    'SELECT a.id AS ID, p.sku AS "SKU", w.code AS "Depósito", a.counted_quantity AS "Contagem", ' +
    'COALESCE(b.on_hand, CAST(0 AS NUMERIC(15,3))) AS "Saldo atual", a.reason AS "Justificativa", u.username AS "Solicitante", a.requested_at AS "Data" ' +
    'FROM stock_adjustments a JOIN products p ON p.id = a.product_id JOIN warehouses w ON w.id = a.warehouse_id ' +
    'JOIN users u ON u.id = a.requested_by ' +
    'LEFT JOIN stock_balances b ON b.product_id = a.product_id AND b.warehouse_id = a.warehouse_id ' +
    'WHERE a.status = ''PENDING'' ORDER BY a.id');
end;

function TReadModel.SalesOrders(const AStatus: string): TDataTable;
begin
  Result := Run(
    'SELECT FIRST 500 o.id AS ID, o.id AS "Pedido", c.name AS "Cliente", o.status AS "Status", o.total AS "Total", ' +
    'o.installments AS "Parcelas", u.username AS "Vendedor", o.updated_at AS "Atualizado" ' +
    'FROM sales_orders o JOIN customers c ON c.id = o.customer_id JOIN users u ON u.id = o.seller_id ' +
    'WHERE (CAST(:status AS VARCHAR(10)) = '''' OR o.status = :status) ORDER BY o.updated_at DESC',
    [P('status', AStatus)]);
end;

function TReadModel.SalesOrderItems(const AOrderId: Int64): TDataTable;
begin
  Result := Run(
    'SELECT i.id AS ID, p.sku AS "SKU", p.name AS "Produto", w.code AS "Depósito", i.quantity AS "Quantidade", ' +
    'i.unit_price AS "Preço unitário", i.line_total AS "Total", r.status AS "Reserva" ' +
    'FROM sales_order_items i JOIN products p ON p.id = i.product_id JOIN warehouses w ON w.id = i.warehouse_id ' +
    'LEFT JOIN stock_reservations r ON r.sales_order_item_id = i.id WHERE i.sales_order_id = :order_id ORDER BY i.id',
    [P('order_id', AOrderId)]);
end;

function TReadModel.SalesOrderHistory(const AOrderId: Int64): TDataTable;
begin
  Result := Run(
    'SELECT h.occurred_at AS "Data", h.from_status AS "De", h.to_status AS "Para", u.username AS "Usuário", h.reason AS "Motivo" ' +
    'FROM sales_order_status_history h JOIN users u ON u.id = h.user_id WHERE h.sales_order_id = :order_id ORDER BY h.id',
    [P('order_id', AOrderId)]);
end;

function TReadModel.PurchaseOrders: TDataTable;
begin
  Result := Run(
    'SELECT FIRST 500 o.id AS ID, o.id AS "Pedido", s.name AS "Fornecedor", w.code AS "Depósito", o.status AS "Status", o.created_at AS "Criado" ' +
    'FROM purchase_orders o JOIN suppliers s ON s.id = o.supplier_id JOIN warehouses w ON w.id = o.warehouse_id ORDER BY o.id DESC');
end;

function TReadModel.PurchaseOrderItems(const AOrderId: Int64): TDataTable;
begin
  Result := Run(
    'SELECT i.id AS ID, p.sku AS "SKU", p.name AS "Produto", i.quantity_ordered AS "Pedido", i.quantity_received AS "Recebido", ' +
    'CAST(i.quantity_ordered - i.quantity_received AS NUMERIC(15,3)) AS "Falta", i.unit_cost AS "Custo unitário" ' +
    'FROM purchase_order_items i JOIN products p ON p.id = i.product_id WHERE i.purchase_order_id = :order_id ORDER BY p.sku',
    [P('order_id', AOrderId)]);
end;

function TReadModel.PurchaseDivergences: TDataTable;
begin
  Result := Run(
    'SELECT o.id AS "Pedido", s.name AS "Fornecedor", p.sku AS "SKU", i.quantity_ordered AS "Pedido (qtd)", i.quantity_received AS "Recebido", ' +
    'CAST(i.quantity_received - i.quantity_ordered AS NUMERIC(15,3)) AS "Divergência", o.status AS "Status" ' +
    'FROM purchase_order_items i JOIN purchase_orders o ON o.id = i.purchase_order_id JOIN suppliers s ON s.id = o.supplier_id JOIN products p ON p.id = i.product_id ' +
    'WHERE i.quantity_received > i.quantity_ordered OR (o.status = ''CLOSED_SHORT'' AND i.quantity_received < i.quantity_ordered) ORDER BY o.id, p.sku');
end;

function TReadModel.OpenInstallments(const AToday: TDateTime; const AOnlyOverdue: Boolean): TDataTable;
var
  LFilter: string;
begin
  LFilter := '';
  if AOnlyOverdue then
    LFilter := 'AND i.due_date < :today ';
  Result := Run(
    'SELECT i.id AS ID, t.id AS "Título", n.invoice_number AS "Fatura", c.name AS "Cliente", i.installment_no AS "Parcela", i.due_date AS "Vencimento", ' +
    'i.amount AS "Valor", CAST(i.amount - i.principal_paid - i.discount_granted AS NUMERIC(18,2)) AS "Em aberto", ' +
    'CASE WHEN i.due_date < :today THEN CAST(''Vencido'' AS VARCHAR(10)) ELSE CAST(''A vencer'' AS VARCHAR(10)) END AS "Situação" ' +
    'FROM receivable_installments i JOIN receivable_titles t ON t.id = i.title_id JOIN invoices n ON n.id = t.invoice_id JOIN customers c ON c.id = t.customer_id ' +
    'WHERE t.status <> ''CANCELLED'' AND i.amount > i.principal_paid + i.discount_granted ' + LFilter +
    'ORDER BY i.due_date, i.id',
    [PDateOnly('today', AToday)]);
end;

function TReadModel.Settlements(const AInstallmentId: Int64): TDataTable;
begin
  Result := Run(
    'SELECT s.id AS ID, s.paid_on AS "Data", s.principal AS "Principal", s.interest AS "Juros", s.penalty AS "Multa", s.discount AS "Desconto", ' +
    's.reversal_of_id AS "Estorno de", u.username AS "Usuário", s.note AS "Observação" ' +
    'FROM receivable_settlements s JOIN users u ON u.id = s.user_id WHERE s.installment_id = :installment_id ORDER BY s.id',
    [P('installment_id', AInstallmentId)]);
end;

function TReadModel.CashFlow(const AFrom, ATo: TDateTime): TDataTable;
begin
  { Só entradas: contas a pagar não fazem parte do escopo deste projeto. }
  Result := Run(
    'SELECT day_value AS "Data", CAST(SUM(forecast) AS NUMERIC(18,2)) AS "Previsto", CAST(SUM(realized) AS NUMERIC(18,2)) AS "Realizado" FROM (' +
    '  SELECT i.due_date AS day_value, i.amount - i.principal_paid - i.discount_granted AS forecast, CAST(0 AS NUMERIC(18,2)) AS realized ' +
    '  FROM receivable_installments i JOIN receivable_titles t ON t.id = i.title_id ' +
    '  WHERE t.status <> ''CANCELLED'' AND i.due_date BETWEEN :from_date AND :to_date ' +
    '  UNION ALL ' +
    '  SELECT s.paid_on, CAST(0 AS NUMERIC(18,2)), s.principal + s.interest + s.penalty ' +
    '  FROM receivable_settlements s WHERE s.paid_on BETWEEN :from_date AND :to_date' +
    ') GROUP BY day_value ORDER BY day_value',
    [PDateOnly('from_date', AFrom), PDateOnly('to_date', ATo)]);
end;

function TReadModel.OutboxQueue: TDataTable;
begin
  Result := Run(
    'SELECT FIRST 500 id AS ID, event_type AS "Evento", aggregate_id AS "Documento", status AS "Status", attempts AS "Tentativas", ' +
    'next_attempt_at AS "Próxima tentativa", sent_at AS "Enviado em", last_error AS "Último erro" FROM outbox_events ORDER BY id DESC');
end;

function TReadModel.IntegrationLog: TDataTable;
begin
  Result := Run(
    'SELECT FIRST 500 occurred_at AS "Data", http_method AS "Método", url AS "URL", attempt AS "Tentativa", http_status AS "HTTP", ' +
    'duration_ms AS "Duração (ms)", outcome AS "Resultado", correlation_id AS "Correlação", error_message AS "Erro" FROM integration_logs ORDER BY id DESC');
end;

function TReadModel.AuditTrail(const AEntityType: string; const AEntityId: Int64): TDataTable;
begin
  Result := Run(
    'SELECT FIRST 500 a.occurred_at AS "Data", a.action AS "Ação", a.entity_type AS "Entidade", a.entity_id AS "Nº", u.username AS "Usuário", ' +
    'a.correlation_id AS "Correlação", CAST(SUBSTRING(a.details FROM 1 FOR 500) AS VARCHAR(500) CHARACTER SET UTF8) AS "Detalhes" ' +
    'FROM audit_events a LEFT JOIN users u ON u.id = a.user_id ' +
    'WHERE (CAST(:entity_type AS VARCHAR(30)) = '''' OR a.entity_type = :entity_type) AND (CAST(:entity_id AS BIGINT) = 0 OR a.entity_id = :entity_id) ORDER BY a.id DESC',
    [P('entity_type', AEntityType), P('entity_id', AEntityId)]);
end;

function TReadModel.MetricsSummary: TDataTable;
begin
  Result := Run(
    'SELECT metric AS "Métrica", COUNT(*) AS "Eventos", CAST(AVG(duration_ms) AS INTEGER) AS "Duração média (ms)", MAX(duration_ms) AS "Duração máxima (ms)", ' +
    'MAX(occurred_at) AS "Último" FROM metric_events GROUP BY metric ORDER BY metric');
end;

function CsvField(const AValue: string): string;
begin
  Result := AValue;
  if (Pos(';', Result) > 0) or (Pos('"', Result) > 0) or (Pos(#10, Result) > 0) or (Pos(#13, Result) > 0) then
    Result := '"' + StringReplace(Result, '"', '""', [rfReplaceAll]) + '"';
end;

function DataTableToCsv(const ATable: TDataTable): TBytes;
var
  LUtf8: RawByteString;
  LBuilder: string;
  LRow, LColumn: Integer;
begin
  LBuilder := '';
  for LColumn := 0 to High(ATable.Columns) do
  begin
    if LColumn > 0 then
      LBuilder := LBuilder + ';';
    LBuilder := LBuilder + CsvField(ATable.Columns[LColumn]);
  end;
  LBuilder := LBuilder + #13#10;
  for LRow := 0 to High(ATable.Rows) do
  begin
    for LColumn := 0 to High(ATable.Rows[LRow]) do
    begin
      if LColumn > 0 then
        LBuilder := LBuilder + ';';
      LBuilder := LBuilder + CsvField(ATable.Rows[LRow][LColumn]);
    end;
    LBuilder := LBuilder + #13#10;
  end;
  LUtf8 := UTF8Encode(LBuilder);
  SetLength(Result, 3 + Length(LUtf8));
  Result[0] := $EF;
  Result[1] := $BB;
  Result[2] := $BF;
  if Length(LUtf8) > 0 then
    Move(LUtf8[1], Result[3], Length(LUtf8));
end;

procedure SaveDataTableCsv(const ATable: TDataTable; const APath: string);
var
  LStream: TFileStream;
  LContent: TBytes;
begin
  LContent := DataTableToCsv(ATable);
  LStream := TFileStream.Create(APath, fmCreate);
  try
    LStream.WriteBuffer(LContent[0], Length(LContent));
  finally
    LStream.Free;
  end;
end;

end.
