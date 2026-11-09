unit EF.Infrastructure.Repositories.Sales;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Money, EF.Domain.OrderState, EF.Domain.Receivables,
  EF.Application.Ports, EF.Infrastructure.Database;

type
  TOrderRepository = class(TInterfacedObject, IOrderRepository)
  private
    FDb: IDbSession;
    function ReadHeader(const ASql: string; const AOrderId: Int64; out AHeader: TOrderHeader): Boolean;
  public
    constructor Create(const ADb: IDbSession);
    function FindByIdempotencyKey(const AKey: string; out AOrderId: Int64): Boolean;
    function Insert(const AHeader: TOrderHeader): Int64;
    function InsertItem(const AItem: TOrderItem): Int64;
    function Read(const AOrderId: Int64; out AHeader: TOrderHeader): Boolean;
    function Lock(const AOrderId: Int64; out AHeader: TOrderHeader): Boolean;
    function Items(const AOrderId: Int64): TOrderItemArray;
    procedure UpdateStatus(const AOrderId: Int64; const AStatus: TOrderStatus; const ACancelReason: string; const ACarrierId: Int64);
    procedure SetIdempotencyKey(const AOrderId: Int64; const AKey: string);
    procedure AddHistory(const AOrderId: Int64; const AHasFrom: Boolean; const AFrom, ATo: TOrderStatus; const AUserId: Int64; const AReason: string);
    function ReservedTotal(const ACustomerId, AExcludingOrderId: Int64): TMoney;
  end;

  TReceivableRepository = class(TInterfacedObject, IReceivableRepository)
  private
    FDb: IDbSession;
    function ReadInstallmentWith(const ASql: string; const AId: Int64; out AInstallment: TInstallmentRecord): Boolean;
  public
    constructor Create(const ADb: IDbSession);
    function NextInvoiceNumber: Int64;
    function InsertInvoice(const ANumber, AOrderId, ACustomerId: Int64; const ATotal: TMoney; const AUserId: Int64): Int64;
    function FindInvoiceOfOrder(const AOrderId: Int64; out AInvoiceId, ANumber: Int64): Boolean;
    function InsertTitle(const AInvoiceId, ACustomerId: Int64; const ATotal: TMoney): Int64;
    procedure InsertInstallment(const ATitleId: Int64; const APlanned: TPlannedInstallment);
    function ReadInstallment(const AId: Int64; out AInstallment: TInstallmentRecord): Boolean;
    function LockInstallment(const AId: Int64; out AInstallment: TInstallmentRecord): Boolean;
    procedure SaveInstallment(const AInstallment: TInstallmentRecord);
    function LockTitle(const ATitleId: Int64; out ATotal: TMoney): Boolean;
    function TitleSettled(const ATitleId: Int64): TMoney;
    procedure UpdateTitleStatus(const ATitleId: Int64; const AStatus: TTitleStatus);
    function FindSettlementByKey(const AKey: string; out ASettlementId: Int64): Boolean;
    function InsertSettlement(const ASettlement: TSettlementRecord): Int64;
    function ReadSettlement(const AId: Int64; out ASettlement: TSettlementRecord): Boolean;
    function HasReversal(const ASettlementId: Int64): Boolean;
    function OpenBalance(const ACustomerId: Int64): TMoney;
  end;

implementation

{ Firebird 4+: SUM de NUMERIC(18,x) devolve NUMERIC(38,x), um INT128 que drivers antigos
  entregam como NULL. Por isso todo SUM aqui tem CAST explícito (docs/adr/004). }
const
  COrderColumns = 'id, customer_id, seller_id, carrier_id, status, idempotency_key, total, installments, installment_interval_days';
  CInstallmentColumns = 'id, title_id, installment_no, due_date, amount, principal_paid, discount_granted';

constructor TOrderRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

function TOrderRepository.FindByIdempotencyKey(const AKey: string; out AOrderId: Int64): Boolean;
var
  LReader: IDbReader;
begin
  AOrderId := 0;
  LReader := FDb.Query('SELECT id FROM sales_orders WHERE idempotency_key = :key_value', [P('key_value', AKey)]);
  Result := not LReader.Eof;
  if Result then
    AOrderId := LReader.Int('id');
end;

function TOrderRepository.Insert(const AHeader: TOrderHeader): Int64;
begin
  Result := FDb.NextId('seq_sales_orders');
  FDb.Execute(
    'INSERT INTO sales_orders (id, customer_id, seller_id, carrier_id, status, idempotency_key, total, installments, installment_interval_days) ' +
    'VALUES (:id, :customer_id, :seller_id, :carrier_id, :status, :key_value, :total, :installments, :interval_days)',
    [P('id', Result), P('customer_id', AHeader.CustomerId), P('seller_id', AHeader.SellerId), PIdOrNull('carrier_id', AHeader.CarrierId),
     P('status', TOrderStateMachine.ToCode(AHeader.Status)), PTextOrNull('key_value', AHeader.IdempotencyKey), P('total', AHeader.Total),
     P('installments', Int64(AHeader.Installments)), P('interval_days', Int64(AHeader.IntervalDays))]);
end;

function TOrderRepository.InsertItem(const AItem: TOrderItem): Int64;
begin
  Result := FDb.NextId('seq_sales_order_items');
  FDb.Execute(
    'INSERT INTO sales_order_items (id, sales_order_id, product_id, warehouse_id, quantity, unit_price, line_total) ' +
    'VALUES (:id, :order_id, :product_id, :warehouse_id, :quantity, :unit_price, :line_total)',
    [P('id', Result), P('order_id', AItem.OrderId), P('product_id', AItem.ProductId), P('warehouse_id', AItem.WarehouseId),
     P('quantity', AItem.Quantity), P('unit_price', AItem.UnitPrice), P('line_total', AItem.LineTotal)]);
end;

function TOrderRepository.ReadHeader(const ASql: string; const AOrderId: Int64; out AHeader: TOrderHeader): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query(ASql, [P('id', AOrderId)]);
  Result := not LReader.Eof;
  if Result then
  begin
    AHeader.Id := LReader.Int('id');
    AHeader.CustomerId := LReader.Int('customer_id');
    AHeader.SellerId := LReader.Int('seller_id');
    AHeader.CarrierId := LReader.Int('carrier_id');
    AHeader.Status := TOrderStateMachine.FromCode(LReader.Str('status'));
    AHeader.IdempotencyKey := LReader.Str('idempotency_key');
    AHeader.Total := LReader.Money('total');
    AHeader.Installments := LReader.Int('installments');
    AHeader.IntervalDays := LReader.Int('installment_interval_days');
  end;
end;

function TOrderRepository.Read(const AOrderId: Int64; out AHeader: TOrderHeader): Boolean;
begin
  Result := ReadHeader('SELECT ' + COrderColumns + ' FROM sales_orders WHERE id = :id', AOrderId, AHeader);
end;

function TOrderRepository.Lock(const AOrderId: Int64; out AHeader: TOrderHeader): Boolean;
begin
  Result := ReadHeader('SELECT ' + COrderColumns + ' FROM sales_orders WHERE id = :id WITH LOCK', AOrderId, AHeader);
end;

function TOrderRepository.Items(const AOrderId: Int64): TOrderItemArray;
var
  LReader: IDbReader;
  LCount: Integer;
begin
  LReader := FDb.Query(
    'SELECT id, sales_order_id, product_id, warehouse_id, quantity, unit_price, line_total FROM sales_order_items ' +
    'WHERE sales_order_id = :order_id ORDER BY product_id, warehouse_id',
    [P('order_id', AOrderId)]);
  LCount := 0;
  SetLength(Result, 0);
  while not LReader.Eof do
  begin
    SetLength(Result, LCount + 1);
    Result[LCount].Id := LReader.Int('id');
    Result[LCount].OrderId := LReader.Int('sales_order_id');
    Result[LCount].ProductId := LReader.Int('product_id');
    Result[LCount].WarehouseId := LReader.Int('warehouse_id');
    Result[LCount].Quantity := LReader.Qty('quantity');
    Result[LCount].UnitPrice := LReader.Money('unit_price');
    Result[LCount].LineTotal := LReader.Money('line_total');
    Inc(LCount);
    LReader.Next;
  end;
end;

procedure TOrderRepository.UpdateStatus(const AOrderId: Int64; const AStatus: TOrderStatus; const ACancelReason: string; const ACarrierId: Int64);
begin
  FDb.Execute(
    'UPDATE sales_orders SET status = :status, cancel_reason = COALESCE(:reason, cancel_reason), ' +
    'carrier_id = COALESCE(:carrier_id, carrier_id), updated_at = LOCALTIMESTAMP WHERE id = :id',
    [P('status', TOrderStateMachine.ToCode(AStatus)), PTextOrNull('reason', ACancelReason), PIdOrNull('carrier_id', ACarrierId), P('id', AOrderId)]);
end;

procedure TOrderRepository.SetIdempotencyKey(const AOrderId: Int64; const AKey: string);
begin
  FDb.Execute('UPDATE sales_orders SET idempotency_key = :key_value WHERE id = :id', [P('key_value', AKey), P('id', AOrderId)]);
end;

procedure TOrderRepository.AddHistory(const AOrderId: Int64; const AHasFrom: Boolean; const AFrom, ATo: TOrderStatus; const AUserId: Int64; const AReason: string);
var
  LFrom: TDbParam;
begin
  if AHasFrom then
    LFrom := P('from_status', TOrderStateMachine.ToCode(AFrom))
  else
    LFrom := PNull('from_status');
  FDb.Execute(
    'INSERT INTO sales_order_status_history (id, sales_order_id, from_status, to_status, user_id, reason) ' +
    'VALUES (NEXT VALUE FOR seq_order_status_history, :order_id, :from_status, :to_status, :user_id, :reason)',
    [P('order_id', AOrderId), LFrom, P('to_status', TOrderStateMachine.ToCode(ATo)), P('user_id', AUserId), PTextOrNull('reason', AReason)]);
end;

function TOrderRepository.ReservedTotal(const ACustomerId, AExcludingOrderId: Int64): TMoney;
begin
  Result := FDb.Query(
    'SELECT CAST(COALESCE(SUM(total), 0) AS NUMERIC(18,2)) AS total FROM sales_orders WHERE customer_id = :customer_id AND id <> :excluding ' +
    'AND status IN (''CONFIRMED'', ''RESERVED'', ''PICKING'', ''SHIPPED'')',
    [P('customer_id', ACustomerId), P('excluding', AExcludingOrderId)]).Money('total');
end;

constructor TReceivableRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

function TReceivableRepository.NextInvoiceNumber: Int64;
begin
  Result := FDb.NextId('seq_invoice_number');
end;

function TReceivableRepository.InsertInvoice(const ANumber, AOrderId, ACustomerId: Int64; const ATotal: TMoney; const AUserId: Int64): Int64;
begin
  Result := FDb.NextId('seq_invoices');
  FDb.Execute(
    'INSERT INTO invoices (id, invoice_number, sales_order_id, customer_id, total, issued_by) VALUES (:id, :number_value, :order_id, :customer_id, :total, :user_id)',
    [P('id', Result), P('number_value', ANumber), P('order_id', AOrderId), P('customer_id', ACustomerId), P('total', ATotal), P('user_id', AUserId)]);
end;

function TReceivableRepository.FindInvoiceOfOrder(const AOrderId: Int64; out AInvoiceId, ANumber: Int64): Boolean;
var
  LReader: IDbReader;
begin
  AInvoiceId := 0;
  ANumber := 0;
  LReader := FDb.Query('SELECT id, invoice_number FROM invoices WHERE sales_order_id = :order_id', [P('order_id', AOrderId)]);
  Result := not LReader.Eof;
  if Result then
  begin
    AInvoiceId := LReader.Int('id');
    ANumber := LReader.Int('invoice_number');
  end;
end;

function TReceivableRepository.InsertTitle(const AInvoiceId, ACustomerId: Int64; const ATotal: TMoney): Int64;
begin
  Result := FDb.NextId('seq_receivable_titles');
  FDb.Execute(
    'INSERT INTO receivable_titles (id, invoice_id, customer_id, total) VALUES (:id, :invoice_id, :customer_id, :total)',
    [P('id', Result), P('invoice_id', AInvoiceId), P('customer_id', ACustomerId), P('total', ATotal)]);
end;

procedure TReceivableRepository.InsertInstallment(const ATitleId: Int64; const APlanned: TPlannedInstallment);
begin
  FDb.Execute(
    'INSERT INTO receivable_installments (id, title_id, installment_no, due_date, amount) VALUES (NEXT VALUE FOR seq_receivable_installments, :title_id, :no, :due_date, :amount)',
    [P('title_id', ATitleId), P('no', Int64(APlanned.Number)), PDateOnly('due_date', APlanned.DueDate), P('amount', APlanned.Amount)]);
end;

function TReceivableRepository.ReadInstallmentWith(const ASql: string; const AId: Int64; out AInstallment: TInstallmentRecord): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query(ASql, [P('id', AId)]);
  Result := not LReader.Eof;
  if Result then
  begin
    AInstallment.Id := LReader.Int('id');
    AInstallment.TitleId := LReader.Int('title_id');
    AInstallment.Number := LReader.Int('installment_no');
    AInstallment.DueDate := LReader.Date('due_date');
    AInstallment.State.Amount := LReader.Money('amount');
    AInstallment.State.PrincipalPaid := LReader.Money('principal_paid');
    AInstallment.State.DiscountGranted := LReader.Money('discount_granted');
  end;
end;

function TReceivableRepository.ReadInstallment(const AId: Int64; out AInstallment: TInstallmentRecord): Boolean;
begin
  Result := ReadInstallmentWith('SELECT ' + CInstallmentColumns + ' FROM receivable_installments WHERE id = :id', AId, AInstallment);
end;

function TReceivableRepository.LockInstallment(const AId: Int64; out AInstallment: TInstallmentRecord): Boolean;
begin
  Result := ReadInstallmentWith('SELECT ' + CInstallmentColumns + ' FROM receivable_installments WHERE id = :id WITH LOCK', AId, AInstallment);
end;

procedure TReceivableRepository.SaveInstallment(const AInstallment: TInstallmentRecord);
begin
  FDb.Execute(
    'UPDATE receivable_installments SET principal_paid = :paid, discount_granted = :discount WHERE id = :id',
    [P('paid', AInstallment.State.PrincipalPaid), P('discount', AInstallment.State.DiscountGranted), P('id', AInstallment.Id)]);
end;

function TReceivableRepository.LockTitle(const ATitleId: Int64; out ATotal: TMoney): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query('SELECT total FROM receivable_titles WHERE id = :id WITH LOCK', [P('id', ATitleId)]);
  Result := not LReader.Eof;
  if Result then
    ATotal := LReader.Money('total');
end;

function TReceivableRepository.TitleSettled(const ATitleId: Int64): TMoney;
begin
  Result := FDb.Query(
    'SELECT CAST(COALESCE(SUM(principal_paid + discount_granted), 0) AS NUMERIC(18,2)) AS settled FROM receivable_installments WHERE title_id = :title_id',
    [P('title_id', ATitleId)]).Money('settled');
end;

procedure TReceivableRepository.UpdateTitleStatus(const ATitleId: Int64; const AStatus: TTitleStatus);
begin
  FDb.Execute('UPDATE receivable_titles SET status = :status WHERE id = :id', [P('status', TitleStatusCode(AStatus)), P('id', ATitleId)]);
end;

function TReceivableRepository.FindSettlementByKey(const AKey: string; out ASettlementId: Int64): Boolean;
var
  LReader: IDbReader;
begin
  ASettlementId := 0;
  LReader := FDb.Query('SELECT id FROM receivable_settlements WHERE idempotency_key = :key_value', [P('key_value', AKey)]);
  Result := not LReader.Eof;
  if Result then
    ASettlementId := LReader.Int('id');
end;

function TReceivableRepository.InsertSettlement(const ASettlement: TSettlementRecord): Int64;
begin
  Result := FDb.NextId('seq_receivable_settlements');
  FDb.Execute(
    'INSERT INTO receivable_settlements (id, installment_id, principal, interest, penalty, discount, paid_on, user_id, idempotency_key, reversal_of_id, note) ' +
    'VALUES (:id, :installment_id, :principal, :interest, :penalty, :discount, :paid_on, :user_id, :key_value, :reversal_of_id, :note)',
    [P('id', Result), P('installment_id', ASettlement.InstallmentId), P('principal', ASettlement.Principal), P('interest', ASettlement.Interest),
     P('penalty', ASettlement.Penalty), P('discount', ASettlement.Discount), PDateOnly('paid_on', ASettlement.PaidOn), P('user_id', ASettlement.UserId),
     P('key_value', ASettlement.IdempotencyKey), PIdOrNull('reversal_of_id', ASettlement.ReversalOfId), PTextOrNull('note', ASettlement.Note)]);
end;

function TReceivableRepository.ReadSettlement(const AId: Int64; out ASettlement: TSettlementRecord): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query(
    'SELECT id, installment_id, principal, interest, penalty, discount, paid_on, user_id, idempotency_key, reversal_of_id, note FROM receivable_settlements WHERE id = :id',
    [P('id', AId)]);
  Result := not LReader.Eof;
  if Result then
  begin
    ASettlement.Id := LReader.Int('id');
    ASettlement.InstallmentId := LReader.Int('installment_id');
    ASettlement.Principal := LReader.Money('principal');
    ASettlement.Interest := LReader.Money('interest');
    ASettlement.Penalty := LReader.Money('penalty');
    ASettlement.Discount := LReader.Money('discount');
    ASettlement.PaidOn := LReader.Date('paid_on');
    ASettlement.UserId := LReader.Int('user_id');
    ASettlement.IdempotencyKey := LReader.Str('idempotency_key');
    ASettlement.ReversalOfId := LReader.Int('reversal_of_id');
    ASettlement.Note := LReader.Str('note');
  end;
end;

function TReceivableRepository.HasReversal(const ASettlementId: Int64): Boolean;
begin
  Result := not FDb.Query('SELECT 1 AS x FROM receivable_settlements WHERE reversal_of_id = :id', [P('id', ASettlementId)]).Eof;
end;

function TReceivableRepository.OpenBalance(const ACustomerId: Int64): TMoney;
begin
  Result := FDb.Query(
    'SELECT CAST(COALESCE(SUM(i.amount - i.principal_paid - i.discount_granted), 0) AS NUMERIC(18,2)) AS open_balance ' +
    'FROM receivable_installments i JOIN receivable_titles t ON t.id = i.title_id ' +
    'WHERE t.customer_id = :customer_id AND t.status <> ''CANCELLED''',
    [P('customer_id', ACustomerId)]).Money('open_balance');
end;

end.
