unit EF.Application.Sales;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Money, EF.Domain.Quantity, EF.Domain.OrderState,
  EF.Application.Ports, EF.Application.Base;

type
  TOrderLineInput = record
    ProductId, WarehouseId: Int64;
    Quantity: TQuantity;
  end;
  TOrderLineInputs = array of TOrderLineInput;

  TNewOrderCommand = record
    CustomerId, CarrierId: Int64;
    Lines: TOrderLineInputs;
    Installments, IntervalDays: Integer;
    IdempotencyKey: string;
  end;

  TConfirmResult = record
    OrderId: Int64;
    { True: a operação já tinha acontecido e nada novo foi gravado. }
    AlreadyProcessed: Boolean;
  end;

  TSalesService = class(TServiceBase)
  private
    function PriceLines(const ALines: TOrderLineInputs): TOrderItemArray;
    function InsertOrder(const ACommand: TNewOrderCommand; const AItems: TOrderItemArray; const AKey: string): Int64;
    procedure Transition(const AOrderId: Int64; const AFrom, ATo: TOrderStatus; const AReason: string = ''; const ACarrierId: Int64 = 0);
    procedure EnsureCredit(const ACustomer: TCustomerRecord; const ATotal: TMoney; const AExcludingOrderId: Int64);
    procedure LockAndValidateStock(const AItems: TOrderItemArray);
    procedure ReserveItems(const AOrderId: Int64; const AItems: TOrderItemArray);
    function LockActiveCustomer(const ACustomerId: Int64): TCustomerRecord;
    procedure Fulfill(const AOrderId: Int64; const ATo: TOrderStatus; const AAction: string; const ACarrierId: Int64);
  public
    function CreateDraft(const ACommand: TNewOrderCommand): Int64;
    { Fluxo crítico: cria e reserva em uma única transação. Exige IdempotencyKey. }
    function ConfirmNew(const ACommand: TNewOrderCommand): TConfirmResult;
    function ConfirmDraft(const AOrderId: Int64; const AIdempotencyKey: string): TConfirmResult;
    procedure StartPicking(const AOrderId: Int64);
    procedure Ship(const AOrderId, ACarrierId: Int64);
    procedure Cancel(const AOrderId: Int64; const AReason: string);
  end;

{ Ordena por produto e depósito: a ordem global de bloqueio que evita deadlock. }
procedure SortOrderItems(var AItems: TOrderItemArray);

implementation

uses
  EF.Domain.Exceptions, EF.Domain.Stock, EF.Domain.Policies,
  EF.Application.StockLedger,
  EF.Shared.Logging, EF.Shared.Text;

procedure SortOrderItems(var AItems: TOrderItemArray);
var
  LOuter, LInner: Integer;
  LCurrent: TOrderItem;

  function ComesAfter(const A, B: TOrderItem): Boolean;
  begin
    Result := (A.ProductId > B.ProductId) or ((A.ProductId = B.ProductId) and (A.WarehouseId > B.WarehouseId));
  end;

begin
  for LOuter := 1 to High(AItems) do
  begin
    LCurrent := AItems[LOuter];
    LInner := LOuter - 1;
    while (LInner >= 0) and ComesAfter(AItems[LInner], LCurrent) do
    begin
      AItems[LInner + 1] := AItems[LInner];
      Dec(LInner);
    end;
    AItems[LInner + 1] := LCurrent;
  end;
end;

function TSalesService.PriceLines(const ALines: TOrderLineInputs): TOrderItemArray;
var
  LIndex: Integer;
  LProduct: TProductRecord;
begin
  if Length(ALines) = 0 then
    raise EValidationError.Create('O pedido precisa de ao menos um item.');
  SetLength(Result, Length(ALines));
  for LIndex := 0 to High(ALines) do
  begin
    if not ALines[LIndex].Quantity.IsPositive then
      raise EValidationError.Create('A quantidade de cada item deve ser maior que zero.');
    if not FUow.Catalog.ReadProduct(ALines[LIndex].ProductId, LProduct) then
      raise ENotFound.CreateFmt('Produto %d não encontrado.', [ALines[LIndex].ProductId]);
    if not LProduct.IsActive then
      raise EValidationError.CreateFmt('Produto %s está inativo.', [LProduct.Sku]);
    if (not LProduct.AllowsFraction) and (ALines[LIndex].Quantity.Thousandths mod 1000 <> 0) then
      raise EValidationError.CreateFmt('Produto %s é vendido em %s: não aceita quantidade fracionada.', [LProduct.Sku, LProduct.UnitCode]);
    if not FUow.Catalog.WarehouseIsActive(ALines[LIndex].WarehouseId) then
      raise EValidationError.CreateFmt('Depósito %d inexistente ou inativo.', [ALines[LIndex].WarehouseId]);
    Result[LIndex].Id := 0;
    Result[LIndex].OrderId := 0;
    Result[LIndex].ProductId := ALines[LIndex].ProductId;
    Result[LIndex].WarehouseId := ALines[LIndex].WarehouseId;
    Result[LIndex].Quantity := ALines[LIndex].Quantity;
    Result[LIndex].UnitPrice := LProduct.SalePrice;
    Result[LIndex].LineTotal := LProduct.SalePrice.Times(ALines[LIndex].Quantity);
  end;
  SortOrderItems(Result);
  for LIndex := 1 to High(Result) do
    if (Result[LIndex].ProductId = Result[LIndex - 1].ProductId) and (Result[LIndex].WarehouseId = Result[LIndex - 1].WarehouseId) then
      raise EValidationError.Create('O mesmo produto aparece duas vezes para o mesmo depósito. Some as quantidades.');
end;

function SumItems(const AItems: TOrderItemArray): TMoney;
var
  LIndex: Integer;
begin
  Result := TMoney.Zero;
  for LIndex := 0 to High(AItems) do
    Result := Result + AItems[LIndex].LineTotal;
end;

function TSalesService.InsertOrder(const ACommand: TNewOrderCommand; const AItems: TOrderItemArray; const AKey: string): Int64;
var
  LHeader: TOrderHeader;
  LIndex: Integer;
  LItem: TOrderItem;
begin
  LHeader.Id := 0;
  LHeader.CustomerId := ACommand.CustomerId;
  LHeader.SellerId := FCtx.UserId;
  LHeader.CarrierId := ACommand.CarrierId;
  LHeader.Status := osDraft;
  LHeader.IdempotencyKey := AKey;
  LHeader.Total := SumItems(AItems);
  LHeader.Installments := ACommand.Installments;
  LHeader.IntervalDays := ACommand.IntervalDays;
  if LHeader.Installments = 0 then
    LHeader.Installments := 1;
  if LHeader.IntervalDays = 0 then
    LHeader.IntervalDays := 30;
  Result := FUow.Orders.Insert(LHeader);
  FUow.Orders.AddHistory(Result, False, osDraft, osDraft, FCtx.UserId, '');
  for LIndex := 0 to High(AItems) do
  begin
    LItem := AItems[LIndex];
    LItem.OrderId := Result;
    FUow.Orders.InsertItem(LItem);
  end;
end;

procedure TSalesService.Transition(const AOrderId: Int64; const AFrom, ATo: TOrderStatus; const AReason: string; const ACarrierId: Int64);
begin
  TOrderStateMachine.EnsureTransition(AFrom, ATo);
  FUow.Orders.UpdateStatus(AOrderId, ATo, AReason, ACarrierId);
  FUow.Orders.AddHistory(AOrderId, True, AFrom, ATo, FCtx.UserId, AReason);
end;

procedure TSalesService.EnsureCredit(const ACustomer: TCustomerRecord; const ATotal: TMoney; const AExcludingOrderId: Int64);
var
  LExposure: TMoney;
begin
  if FUow.Settings.GetText('credit_check_enabled', '1') <> '1' then
    Exit;
  LExposure := FUow.Receivables.OpenBalance(ACustomer.Id) + FUow.Orders.ReservedTotal(ACustomer.Id, AExcludingOrderId);
  try
    TCreditPolicy.Ensure(ACustomer.CreditLimit, LExposure, ATotal);
  except
    on E: ECreditLimitExceeded do
      raise ECreditLimitExceeded.CreateFmt('Cliente %s sem limite. %s', [ACustomer.Name, E.Message]);
  end;
end;

procedure TSalesService.LockAndValidateStock(const AItems: TOrderItemArray);
var
  LLedger: TStockLedger;
  LIndex: Integer;
begin
  LLedger := TStockLedger.Make(FUow.Stock, FCtx);
  for LIndex := 0 to High(AItems) do
    LLedger.LockAndEnsureAvailable(AItems[LIndex].ProductId, AItems[LIndex].WarehouseId, AItems[LIndex].Quantity);
end;

procedure TSalesService.ReserveItems(const AOrderId: Int64; const AItems: TOrderItemArray);
var
  LLedger: TStockLedger;
  LIndex: Integer;
  LReservation: TReservationRecord;
  LPersisted: TOrderItemArray;
begin
  LLedger := TStockLedger.Make(FUow.Stock, FCtx);
  LPersisted := FUow.Orders.Items(AOrderId);
  for LIndex := 0 to High(LPersisted) do
  begin
    LLedger.Reserve(LPersisted[LIndex].ProductId, LPersisted[LIndex].WarehouseId, LPersisted[LIndex].Quantity,
      TStockSource.Make('SALES_ORDER', AOrderId, 'Reserva do pedido ' + IntToStr(AOrderId)));
    LReservation.Id := 0;
    LReservation.OrderId := AOrderId;
    LReservation.ItemId := LPersisted[LIndex].Id;
    LReservation.ProductId := LPersisted[LIndex].ProductId;
    LReservation.WarehouseId := LPersisted[LIndex].WarehouseId;
    LReservation.Quantity := LPersisted[LIndex].Quantity;
    LReservation.Status := rsActive;
    FUow.Stock.AddReservation(LReservation);
  end;
end;

function TSalesService.LockActiveCustomer(const ACustomerId: Int64): TCustomerRecord;
begin
  { Cliente primeiro: duas vendas simultâneas do mesmo cliente não estouram o limite. }
  if not FUow.Catalog.LockCustomer(ACustomerId, Result) then
    raise ENotFound.CreateFmt('Cliente %d não encontrado.', [ACustomerId]);
  if not Result.IsActive then
    raise EValidationError.CreateFmt('Cliente %s está inativo.', [Result.Name]);
end;

function TSalesService.CreateDraft(const ACommand: TNewOrderCommand): Int64;
var
  LItems: TOrderItemArray;
begin
  BeginOperation(PermOrderCreate);
  FUow.StartTransaction;
  try
    LItems := PriceLines(ACommand.Lines);
    Result := InsertOrder(ACommand, LItems, '');
    Audit('order.draft_created', 'sales_order', Result);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

function TSalesService.ConfirmNew(const ACommand: TNewOrderCommand): TConfirmResult;
var
  LStart: Int64;
  LCustomer: TCustomerRecord;
  LItems: TOrderItemArray;
  LCommitted: Boolean;
begin
  BeginOperation(PermOrderConfirm);
  if Trim(ACommand.IdempotencyKey) = '' then
    raise EValidationError.Create('Confirmação exige chave de idempotência.');
  LStart := NowTick;
  LCommitted := False;
  Result.OrderId := 0;
  Result.AlreadyProcessed := False;
  FUow.StartTransaction;
  try
    if FUow.Orders.FindByIdempotencyKey(ACommand.IdempotencyKey, Result.OrderId) then
    begin
      Result.AlreadyProcessed := True;
      FUow.Commit;
      Exit;
    end;
    LCustomer := LockActiveCustomer(ACommand.CustomerId);
    { Quem repetiu a chave esperou no bloqueio acima: agora enxerga o que o outro gravou. }
    if FUow.Orders.FindByIdempotencyKey(ACommand.IdempotencyKey, Result.OrderId) then
    begin
      Result.AlreadyProcessed := True;
      FUow.Commit;
      Exit;
    end;
    LItems := PriceLines(ACommand.Lines);
    LockAndValidateStock(LItems);
    EnsureCredit(LCustomer, SumItems(LItems), 0);
    Result.OrderId := InsertOrder(ACommand, LItems, ACommand.IdempotencyKey);
    Transition(Result.OrderId, osDraft, osConfirmed);
    ReserveItems(Result.OrderId, LItems);
    Transition(Result.OrderId, osConfirmed, osReserved);
    Audit('order.confirmed', 'sales_order', Result.OrderId, TJsonObjectBuilder.New.Str('total', SumItems(LItems).ToInvariant).Int('items', Length(LItems)).ToJson);
    FUow.Commit;
    LCommitted := True;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      { Outra confirmação com a mesma chave venceu a corrida: devolve o pedido dela. }
      FUow.StartTransaction;
      try
        Result.AlreadyProcessed := FUow.Orders.FindByIdempotencyKey(ACommand.IdempotencyKey, Result.OrderId);
        FUow.Commit;
      except
        FUow.Rollback;
        raise;
      end;
      if not Result.AlreadyProcessed then
        raise;
    end;
    on E: EInsufficientStock do
    begin
      FUow.Rollback;
      RecordMetric('reservation_refused', E.Message, LStart);
      LogEvent(llInfo, 'order.reservation_refused', TJsonObjectBuilder.New.Str('reason', E.Message).ToJson);
      raise;
    end;
    on E: EConcurrencyConflict do
    begin
      FUow.Rollback;
      RecordMetric('concurrency_conflict', 'confirm_order', LStart);
      raise;
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
  if LCommitted then
  begin
    RecordMetric('order_confirmed', IntToStr(Result.OrderId), LStart);
    LogEvent(llInfo, 'order.confirmed', TJsonObjectBuilder.New.Int('order_id', Result.OrderId).Int('duration_ms', ElapsedSince(LStart)).ToJson);
  end;
end;

function TSalesService.ConfirmDraft(const AOrderId: Int64; const AIdempotencyKey: string): TConfirmResult;
var
  LStart: Int64;
  LHeader: TOrderHeader;
  LCustomer: TCustomerRecord;
  LItems: TOrderItemArray;
begin
  BeginOperation(PermOrderConfirm);
  LStart := NowTick;
  Result.OrderId := AOrderId;
  Result.AlreadyProcessed := False;
  FUow.StartTransaction;
  try
    if not FUow.Orders.Read(AOrderId, LHeader) then
      raise ENotFound.CreateFmt('Pedido %d não encontrado.', [AOrderId]);
    LCustomer := LockActiveCustomer(LHeader.CustomerId);
    FUow.Orders.Lock(AOrderId, LHeader);
    if LHeader.Status in [osReserved, osPicking, osShipped, osInvoiced] then
    begin
      Result.AlreadyProcessed := True;
      FUow.Commit;
      Exit;
    end;
    TOrderStateMachine.EnsureTransition(LHeader.Status, osConfirmed);
    LItems := FUow.Orders.Items(AOrderId);
    LockAndValidateStock(LItems);
    EnsureCredit(LCustomer, LHeader.Total, AOrderId);
    if AIdempotencyKey <> '' then
      FUow.Orders.SetIdempotencyKey(AOrderId, AIdempotencyKey);
    Transition(AOrderId, osDraft, osConfirmed);
    ReserveItems(AOrderId, LItems);
    Transition(AOrderId, osConfirmed, osReserved);
    Audit('order.confirmed', 'sales_order', AOrderId, TJsonObjectBuilder.New.Str('total', LHeader.Total.ToInvariant).Int('items', Length(LItems)).ToJson);
    FUow.Commit;
  except
    on E: EInsufficientStock do
    begin
      FUow.Rollback;
      RecordMetric('reservation_refused', E.Message, LStart);
      raise;
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
  if not Result.AlreadyProcessed then
    RecordMetric('order_confirmed', IntToStr(AOrderId), LStart);
end;

procedure TSalesService.Fulfill(const AOrderId: Int64; const ATo: TOrderStatus; const AAction: string; const ACarrierId: Int64);
var
  LHeader: TOrderHeader;
begin
  BeginOperation(PermOrderFulfill);
  FUow.StartTransaction;
  try
    if not FUow.Orders.Lock(AOrderId, LHeader) then
      raise ENotFound.CreateFmt('Pedido %d não encontrado.', [AOrderId]);
    Transition(AOrderId, LHeader.Status, ATo, '', ACarrierId);
    Audit(AAction, 'sales_order', AOrderId);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

procedure TSalesService.StartPicking(const AOrderId: Int64);
begin
  Fulfill(AOrderId, osPicking, 'order.picking_started', 0);
end;

procedure TSalesService.Ship(const AOrderId, ACarrierId: Int64);
begin
  Fulfill(AOrderId, osShipped, 'order.shipped', ACarrierId);
end;

procedure TSalesService.Cancel(const AOrderId: Int64; const AReason: string);
var
  LHeader: TOrderHeader;
  LReservations: TReservationArray;
  LLedger: TStockLedger;
  LIndex, LReleased: Integer;
begin
  BeginOperation(PermOrderCancel);
  if Trim(AReason) = '' then
    raise EValidationError.Create('Cancelamento exige motivo.');
  FUow.StartTransaction;
  try
    if not FUow.Orders.Lock(AOrderId, LHeader) then
      raise ENotFound.CreateFmt('Pedido %d não encontrado.', [AOrderId]);
    Transition(AOrderId, LHeader.Status, osCancelled, AReason);
    LLedger := TStockLedger.Make(FUow.Stock, FCtx);
    LReservations := FUow.Stock.ReservationsOfOrder(AOrderId);
    LReleased := 0;
    for LIndex := 0 to High(LReservations) do
      if FUow.Stock.CloseReservation(LReservations[LIndex].Id, rsReleased) then
      begin
        LLedger.Release(LReservations[LIndex].ProductId, LReservations[LIndex].WarehouseId, LReservations[LIndex].Quantity,
          TStockSource.Make('SALES_ORDER', AOrderId, 'Cancelamento do pedido ' + IntToStr(AOrderId) + ': ' + AReason));
        Inc(LReleased);
      end;
    Audit('order.cancelled', 'sales_order', AOrderId, TJsonObjectBuilder.New.Str('reason', AReason).Int('reservations_released', LReleased).ToJson);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

end.
