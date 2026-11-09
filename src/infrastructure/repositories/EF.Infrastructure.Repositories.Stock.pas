unit EF.Infrastructure.Repositories.Stock;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Quantity, EF.Domain.Money, EF.Domain.Stock,
  EF.Application.Ports, EF.Infrastructure.Database;

type
  TStockRepository = class(TInterfacedObject, IStockRepository)
  private
    FDb: IDbSession;
  public
    constructor Create(const ADb: IDbSession);
    procedure EnsureBalance(const AProductId, AWarehouseId: Int64);
    function LockBalance(const AProductId, AWarehouseId: Int64; out ABalance: TStockBalance): Boolean;
    procedure SaveBalance(const AProductId, AWarehouseId: Int64; const ABalance: TStockBalance);
    procedure AddMovement(const AMovement: TMovementRecord);
    function DescribeKey(const AProductId, AWarehouseId: Int64): string;
    function AddReservation(const AReservation: TReservationRecord): Int64;
    function ReservationsOfOrder(const AOrderId: Int64): TReservationArray;
    function CloseReservation(const AReservationId: Int64; const AStatus: TReservationStatus): Boolean;
    function AddTransfer(const AProductId, AFrom, ATo: Int64; const AQuantity: TQuantity; const AReason: string; const AUserId: Int64): Int64;
    function AddAdjustment(const AProductId, AWarehouseId: Int64; const ACounted: TQuantity; const AReason: string; const AUserId: Int64): Int64;
    function LockAdjustment(const AId: Int64; out AAdjustment: TAdjustmentRecord): Boolean;
    procedure DecideAdjustment(const AId: Int64; const AStatus: string; const AUserId: Int64);
  end;

  TPurchaseRepository = class(TInterfacedObject, IPurchaseRepository)
  private
    FDb: IDbSession;
  public
    constructor Create(const ADb: IDbSession);
    function Insert(const ASupplierId, AWarehouseId: Int64; const ANote: string; const AUserId: Int64): Int64;
    function InsertItem(const AOrderId, AProductId: Int64; const AOrdered: TQuantity; const AUnitCost: TMoney): Int64;
    function Lock(const AOrderId: Int64; out AHeader: TPurchaseHeader): Boolean;
    function Items(const AOrderId: Int64): TPurchaseItemArray;
    procedure UpdateItemReceived(const AItemId: Int64; const AReceived: TQuantity);
    procedure UpdateStatus(const AOrderId: Int64; const AStatus: string);
    function FindReceiptByKey(const AKey: string; out AReceiptId: Int64): Boolean;
    function InsertReceipt(const AOrderId: Int64; const AKey, ANote: string; const AUserId: Int64): Int64;
    procedure InsertReceiptItem(const AReceiptId, AItemId: Int64; const AReceived, AOutstandingBefore, ADivergence: TQuantity; const ANote: string);
  end;

implementation

uses
  EF.Domain.Exceptions;

constructor TStockRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

procedure TStockRepository.EnsureBalance(const AProductId, AWarehouseId: Int64);
begin
  try
    FDb.Execute(
      'MERGE INTO stock_balances b ' +
      'USING (SELECT CAST(:product_id AS BIGINT) AS product_id, CAST(:warehouse_id AS BIGINT) AS warehouse_id FROM RDB$DATABASE) s ' +
      'ON b.product_id = s.product_id AND b.warehouse_id = s.warehouse_id ' +
      'WHEN NOT MATCHED THEN INSERT (product_id, warehouse_id, on_hand, reserved) VALUES (s.product_id, s.warehouse_id, 0, 0)',
      [P('product_id', AProductId), P('warehouse_id', AWarehouseId)]);
  except
    { Outra transação criou a mesma linha primeiro: é exatamente o que queríamos. }
    on EDuplicateKey do
      ;
  end;
end;

function TStockRepository.LockBalance(const AProductId, AWarehouseId: Int64; out ABalance: TStockBalance): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query(
    'SELECT on_hand, reserved FROM stock_balances WHERE product_id = :product_id AND warehouse_id = :warehouse_id WITH LOCK',
    [P('product_id', AProductId), P('warehouse_id', AWarehouseId)]);
  Result := not LReader.Eof;
  if Result then
  begin
    ABalance.OnHand := LReader.Qty('on_hand');
    ABalance.Reserved := LReader.Qty('reserved');
  end
  else
  begin
    ABalance.OnHand := TQuantity.Zero;
    ABalance.Reserved := TQuantity.Zero;
  end;
end;

procedure TStockRepository.SaveBalance(const AProductId, AWarehouseId: Int64; const ABalance: TStockBalance);
begin
  FDb.Execute(
    'UPDATE stock_balances SET on_hand = :on_hand, reserved = :reserved, updated_at = LOCALTIMESTAMP ' +
    'WHERE product_id = :product_id AND warehouse_id = :warehouse_id',
    [P('on_hand', ABalance.OnHand), P('reserved', ABalance.Reserved), P('product_id', AProductId), P('warehouse_id', AWarehouseId)]);
end;

procedure TStockRepository.AddMovement(const AMovement: TMovementRecord);
begin
  FDb.Execute(
    'INSERT INTO stock_movements (id, product_id, warehouse_id, movement_type, quantity, on_hand_delta, reserved_delta, ' +
    'on_hand_after, reserved_after, reason, user_id, source_type, source_id, correlation_id) VALUES ' +
    '(NEXT VALUE FOR seq_stock_movements, :product_id, :warehouse_id, :movement_type, :quantity, :on_hand_delta, :reserved_delta, ' +
    ':on_hand_after, :reserved_after, :reason, :user_id, :source_type, :source_id, :correlation_id)',
    [P('product_id', AMovement.ProductId), P('warehouse_id', AMovement.WarehouseId),
     P('movement_type', MovementTypeCode(AMovement.MovementType)), P('quantity', AMovement.Quantity),
     P('on_hand_delta', AMovement.OnHandDelta), P('reserved_delta', AMovement.ReservedDelta),
     P('on_hand_after', AMovement.OnHandAfter), P('reserved_after', AMovement.ReservedAfter),
     P('reason', AMovement.Reason), P('user_id', AMovement.UserId), P('source_type', AMovement.SourceType),
     P('source_id', AMovement.SourceId), PTextOrNull('correlation_id', AMovement.CorrelationId)]);
end;

function TStockRepository.DescribeKey(const AProductId, AWarehouseId: Int64): string;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query(
    'SELECT p.sku, w.code FROM products p, warehouses w WHERE p.id = :product_id AND w.id = :warehouse_id',
    [P('product_id', AProductId), P('warehouse_id', AWarehouseId)]);
  if LReader.Eof then
    Result := Format('produto %d, depósito %d', [AProductId, AWarehouseId])
  else
    Result := LReader.Str('sku') + ' no depósito ' + LReader.Str('code');
end;

function TStockRepository.AddReservation(const AReservation: TReservationRecord): Int64;
begin
  Result := FDb.NextId('seq_stock_reservations');
  FDb.Execute(
    'INSERT INTO stock_reservations (id, sales_order_id, sales_order_item_id, product_id, warehouse_id, quantity) ' +
    'VALUES (:id, :order_id, :item_id, :product_id, :warehouse_id, :quantity)',
    [P('id', Result), P('order_id', AReservation.OrderId), P('item_id', AReservation.ItemId),
     P('product_id', AReservation.ProductId), P('warehouse_id', AReservation.WarehouseId), P('quantity', AReservation.Quantity)]);
end;

function TStockRepository.ReservationsOfOrder(const AOrderId: Int64): TReservationArray;
var
  LReader: IDbReader;
  LCount: Integer;
begin
  { Mesma ordem do bloqueio de saldo, para não inverter a ordem entre transações. }
  LReader := FDb.Query(
    'SELECT id, sales_order_id, sales_order_item_id, product_id, warehouse_id, quantity, status ' +
    'FROM stock_reservations WHERE sales_order_id = :order_id ORDER BY product_id, warehouse_id',
    [P('order_id', AOrderId)]);
  LCount := 0;
  SetLength(Result, 0);
  while not LReader.Eof do
  begin
    SetLength(Result, LCount + 1);
    Result[LCount].Id := LReader.Int('id');
    Result[LCount].OrderId := LReader.Int('sales_order_id');
    Result[LCount].ItemId := LReader.Int('sales_order_item_id');
    Result[LCount].ProductId := LReader.Int('product_id');
    Result[LCount].WarehouseId := LReader.Int('warehouse_id');
    Result[LCount].Quantity := LReader.Qty('quantity');
    Result[LCount].Status := ReservationStatusFromCode(LReader.Str('status'));
    Inc(LCount);
    LReader.Next;
  end;
end;

function TStockRepository.CloseReservation(const AReservationId: Int64; const AStatus: TReservationStatus): Boolean;
begin
  Result := FDb.Execute(
    'UPDATE stock_reservations SET status = :status, closed_at = LOCALTIMESTAMP WHERE id = :id AND status = ''ACTIVE''',
    [P('status', ReservationStatusCode(AStatus)), P('id', AReservationId)]) = 1;
end;

function TStockRepository.AddTransfer(const AProductId, AFrom, ATo: Int64; const AQuantity: TQuantity; const AReason: string; const AUserId: Int64): Int64;
begin
  Result := FDb.NextId('seq_stock_transfers');
  FDb.Execute(
    'INSERT INTO stock_transfers (id, product_id, from_warehouse_id, to_warehouse_id, quantity, reason, user_id) ' +
    'VALUES (:id, :product_id, :from_id, :to_id, :quantity, :reason, :user_id)',
    [P('id', Result), P('product_id', AProductId), P('from_id', AFrom), P('to_id', ATo),
     P('quantity', AQuantity), P('reason', AReason), P('user_id', AUserId)]);
end;

function TStockRepository.AddAdjustment(const AProductId, AWarehouseId: Int64; const ACounted: TQuantity; const AReason: string; const AUserId: Int64): Int64;
begin
  Result := FDb.NextId('seq_stock_adjustments');
  FDb.Execute(
    'INSERT INTO stock_adjustments (id, product_id, warehouse_id, counted_quantity, reason, requested_by) ' +
    'VALUES (:id, :product_id, :warehouse_id, :counted, :reason, :user_id)',
    [P('id', Result), P('product_id', AProductId), P('warehouse_id', AWarehouseId),
     P('counted', ACounted), P('reason', AReason), P('user_id', AUserId)]);
end;

function TStockRepository.LockAdjustment(const AId: Int64; out AAdjustment: TAdjustmentRecord): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query(
    'SELECT id, product_id, warehouse_id, counted_quantity, reason, status, requested_by FROM stock_adjustments WHERE id = :id WITH LOCK',
    [P('id', AId)]);
  Result := not LReader.Eof;
  if Result then
  begin
    AAdjustment.Id := LReader.Int('id');
    AAdjustment.ProductId := LReader.Int('product_id');
    AAdjustment.WarehouseId := LReader.Int('warehouse_id');
    AAdjustment.Counted := LReader.Qty('counted_quantity');
    AAdjustment.Reason := LReader.Str('reason');
    AAdjustment.Status := LReader.Str('status');
    AAdjustment.RequestedBy := LReader.Int('requested_by');
  end;
end;

procedure TStockRepository.DecideAdjustment(const AId: Int64; const AStatus: string; const AUserId: Int64);
begin
  FDb.Execute(
    'UPDATE stock_adjustments SET status = :status, decided_by = :user_id, decided_at = LOCALTIMESTAMP WHERE id = :id',
    [P('status', AStatus), P('user_id', AUserId), P('id', AId)]);
end;

constructor TPurchaseRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

function TPurchaseRepository.Insert(const ASupplierId, AWarehouseId: Int64; const ANote: string; const AUserId: Int64): Int64;
begin
  Result := FDb.NextId('seq_purchase_orders');
  FDb.Execute(
    'INSERT INTO purchase_orders (id, supplier_id, warehouse_id, note, created_by) VALUES (:id, :supplier_id, :warehouse_id, :note, :user_id)',
    [P('id', Result), P('supplier_id', ASupplierId), P('warehouse_id', AWarehouseId), PTextOrNull('note', ANote), P('user_id', AUserId)]);
end;

function TPurchaseRepository.InsertItem(const AOrderId, AProductId: Int64; const AOrdered: TQuantity; const AUnitCost: TMoney): Int64;
begin
  Result := FDb.NextId('seq_purchase_order_items');
  FDb.Execute(
    'INSERT INTO purchase_order_items (id, purchase_order_id, product_id, quantity_ordered, unit_cost) VALUES (:id, :order_id, :product_id, :ordered, :unit_cost)',
    [P('id', Result), P('order_id', AOrderId), P('product_id', AProductId), P('ordered', AOrdered), P('unit_cost', AUnitCost)]);
end;

function TPurchaseRepository.Lock(const AOrderId: Int64; out AHeader: TPurchaseHeader): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query('SELECT id, supplier_id, warehouse_id, status FROM purchase_orders WHERE id = :id WITH LOCK', [P('id', AOrderId)]);
  Result := not LReader.Eof;
  if Result then
  begin
    AHeader.Id := LReader.Int('id');
    AHeader.SupplierId := LReader.Int('supplier_id');
    AHeader.WarehouseId := LReader.Int('warehouse_id');
    AHeader.Status := LReader.Str('status');
  end;
end;

function TPurchaseRepository.Items(const AOrderId: Int64): TPurchaseItemArray;
var
  LReader: IDbReader;
  LCount: Integer;
begin
  LReader := FDb.Query(
    'SELECT id, product_id, quantity_ordered, quantity_received, unit_cost FROM purchase_order_items WHERE purchase_order_id = :order_id ORDER BY product_id',
    [P('order_id', AOrderId)]);
  LCount := 0;
  SetLength(Result, 0);
  while not LReader.Eof do
  begin
    SetLength(Result, LCount + 1);
    Result[LCount].Id := LReader.Int('id');
    Result[LCount].ProductId := LReader.Int('product_id');
    Result[LCount].Ordered := LReader.Qty('quantity_ordered');
    Result[LCount].Received := LReader.Qty('quantity_received');
    Result[LCount].UnitCost := LReader.Money('unit_cost');
    Inc(LCount);
    LReader.Next;
  end;
end;

procedure TPurchaseRepository.UpdateItemReceived(const AItemId: Int64; const AReceived: TQuantity);
begin
  FDb.Execute('UPDATE purchase_order_items SET quantity_received = :received WHERE id = :id', [P('received', AReceived), P('id', AItemId)]);
end;

procedure TPurchaseRepository.UpdateStatus(const AOrderId: Int64; const AStatus: string);
begin
  FDb.Execute('UPDATE purchase_orders SET status = :status WHERE id = :id', [P('status', AStatus), P('id', AOrderId)]);
end;

function TPurchaseRepository.FindReceiptByKey(const AKey: string; out AReceiptId: Int64): Boolean;
var
  LReader: IDbReader;
begin
  AReceiptId := 0;
  LReader := FDb.Query('SELECT id FROM purchase_receipts WHERE idempotency_key = :key_value', [P('key_value', AKey)]);
  Result := not LReader.Eof;
  if Result then
    AReceiptId := LReader.Int('id');
end;

function TPurchaseRepository.InsertReceipt(const AOrderId: Int64; const AKey, ANote: string; const AUserId: Int64): Int64;
begin
  Result := FDb.NextId('seq_purchase_receipts');
  FDb.Execute(
    'INSERT INTO purchase_receipts (id, purchase_order_id, idempotency_key, received_by, note) VALUES (:id, :order_id, :key_value, :user_id, :note)',
    [P('id', Result), P('order_id', AOrderId), P('key_value', AKey), P('user_id', AUserId), PTextOrNull('note', ANote)]);
end;

procedure TPurchaseRepository.InsertReceiptItem(const AReceiptId, AItemId: Int64; const AReceived, AOutstandingBefore, ADivergence: TQuantity; const ANote: string);
begin
  FDb.Execute(
    'INSERT INTO purchase_receipt_items (id, receipt_id, purchase_order_item_id, quantity_received, outstanding_before, divergence, divergence_note) ' +
    'VALUES (NEXT VALUE FOR seq_purchase_receipt_items, :receipt_id, :item_id, :received, :outstanding, :divergence, :note)',
    [P('receipt_id', AReceiptId), P('item_id', AItemId), P('received', AReceived), P('outstanding', AOutstandingBefore),
     P('divergence', ADivergence), PTextOrNull('note', ANote)]);
end;

end.
