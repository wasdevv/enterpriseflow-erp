unit EF.Tests.Stock;

{$I EF.inc}
{$M+}

interface

uses
  SysUtils, DUnitX.TestFramework,
  EF.Infrastructure.Composition, EF.Tests.Support;

type
  TStockIntegrationTests = class(TObject)
  private
    FProductA, FProductB, FWarehouseA, FWarehouseB, FCustomer: Int64;
    FCustomers: array [0 .. 1] of Int64;
    FEnv: ITestEnv;
    procedure ConfirmLastUnit(const AApp: TAppServices; const AIndex: Integer);
    procedure ConfirmOppositeOrder(const AApp: TAppServices; const AIndex: Integer);
    procedure TransferOppositeDirection(const AApp: TAppServices; const AIndex: Integer);
  published
    procedure ReservationAboveAvailableLeavesNoTrace;
    procedure ThreadsRacingForLastUnitNeverOversell;
    procedure ProcessesRacingForLastUnitNeverOversell;
    procedure OrdersLockingInOppositeLineOrderDoNotDeadlock;
    procedure TransfersInOppositeDirectionsDoNotDeadlock;
    procedure TransferMovesBothSidesAtomically;
    procedure FailedTransferChangesNothing;
    procedure AdjustmentRequiresApprovalFromAnotherUser;
    procedure ApprovedAdjustmentEntersKardexWithJustification;
    procedure DatabaseRefusesNegativeBalanceFromDirectSql;
    procedure DatabaseRefusesEditingKardex;
    procedure DatabaseRefusesReopeningClosedReservation;
    procedure ClosingReservationTwiceReportsTheSecondAttempt;
    procedure BalancesReconcileWithKardex;
    procedure MovementRecordsWhoWhyAndSourceDocument;
    procedure PartialReceiptThenCompletion;
    procedure RepeatedReceiptKeyDoesNotAddStockTwice;
    procedure OverReceiptRequiresNoteAndAppearsAsDivergence;
    procedure ClosingShortAppearsAsDivergence;
  end;

implementation

uses
  EF.Application.Ports, EF.Application.Inventory, EF.Domain.Quantity, EF.Domain.Money, EF.Domain.Stock,
  EF.Infrastructure.Database, EF.Tests.Spawn, EF.Shared.Text, DateUtils;

function Quantity(const AText: string): TQuantity;
begin
  Result := TQuantity.Parse(AText);
end;

procedure TStockIntegrationTests.ConfirmLastUnit(const AApp: TAppServices; const AIndex: Integer);
begin
  AApp.Sales.ConfirmNew(OrderCommand(FCustomer, [Line(FProductA, FWarehouseA, '1')], NewCorrelationId));
end;

procedure TStockIntegrationTests.ConfirmOppositeOrder(const AApp: TAppServices; const AIndex: Integer);
var
  LRound: Integer;
begin
  for LRound := 1 to 15 do
    if AIndex mod 2 = 0 then
      AApp.Sales.ConfirmNew(OrderCommand(FCustomers[AIndex], [Line(FProductA, FWarehouseA, '1'), Line(FProductB, FWarehouseA, '1')], NewCorrelationId))
    else
      AApp.Sales.ConfirmNew(OrderCommand(FCustomers[AIndex], [Line(FProductB, FWarehouseA, '1'), Line(FProductA, FWarehouseA, '1')], NewCorrelationId));
end;

procedure TStockIntegrationTests.TransferOppositeDirection(const AApp: TAppServices; const AIndex: Integer);
var
  LRound: Integer;
begin
  for LRound := 1 to 15 do
    if AIndex mod 2 = 0 then
      AApp.Stock.Transfer(FProductA, FWarehouseA, FWarehouseB, Quantity('1'), 'ida')
    else
      AApp.Stock.Transfer(FProductA, FWarehouseB, FWarehouseA, Quantity('1'), 'volta');
end;

procedure TStockIntegrationTests.ReservationAboveAvailableLeavesNoTrace;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse: Int64;
  LRaised, LKey: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '10');
  LKey := LEnv.Key;
  LRaised := '';
  try
    LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '11')], LKey));
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EInsufficientStock', LRaised);
  Assert.AreEqual('10/0', LEnv.Balance(LProduct, LWarehouse));
  Assert.AreEqual(0, LEnv.CountRows('SELECT id FROM sales_orders WHERE idempotency_key = :k', [P('k', LKey)]));
  Assert.AreEqual(0, LEnv.CountRows('SELECT id FROM stock_movements WHERE product_id = :p AND movement_type = ''RESERVE''', [P('p', LProduct)]));
  Assert.IsTrue(LEnv.CountRows('SELECT id FROM metric_events WHERE metric = ''reservation_refused''', []) > 0, 'A recusa precisa sobreviver ao rollback');
end;

procedure TStockIntegrationTests.ThreadsRacingForLastUnitNeverOversell;
var
  LOutcomes: TThreadOutcomes;
begin
  FEnv := NewTestEnv;
  try
    FProductA := FEnv.NewProduct('10,00');
    FWarehouseA := FEnv.NewWarehouse;
    FCustomer := FEnv.NewCustomer;
    FEnv.AddStock(FProductA, FWarehouseA, '1');
    LOutcomes := RunConcurrently(FEnv, 8, ConfirmLastUnit);
    Assert.AreEqual(1, CountOutcome(LOutcomes, ''), 'Exatamente um vencedor: ' + DescribeOutcomes(LOutcomes));
    Assert.AreEqual(7, CountOutcome(LOutcomes, 'EInsufficientStock'), 'Os outros recebem recusa clara: ' + DescribeOutcomes(LOutcomes));
    Assert.AreEqual('1/1', FEnv.Balance(FProductA, FWarehouseA));
    Assert.AreEqual(1, FEnv.CountRows('SELECT id FROM stock_reservations WHERE product_id = :p', [P('p', FProductA)]));
  finally
    FEnv := nil;
  end;
end;

procedure TStockIntegrationTests.ProcessesRacingForLastUnitNeverOversell;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LCustomer, LStartAt: Int64;
  LWorkers: array [0 .. 3] of TSpawned;
  LCodes: array [0 .. 3] of Integer;
  LIndex, LWinners, LRefused: Integer;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LCustomer := LEnv.NewCustomer;
  LEnv.AddStock(LProduct, LWarehouse, '1');
  { Tempo de sobra para os quatro processos subirem e conectarem antes do disparo. }
  LStartAt := MilliSecondsBetween(EncodeDate(1970, 1, 1), Now) + 1500;
  for LIndex := 0 to 3 do
    LWorkers[LIndex] := TSpawned.Start(SiblingExecutable('race_worker'),
      [IntToStr(LEnv.App.Context.UserId), IntToStr(LCustomer), IntToStr(LProduct), IntToStr(LWarehouse), IntToStr(LStartAt)]);
  LWinners := 0;
  LRefused := 0;
  for LIndex := 0 to 3 do
  begin
    LCodes[LIndex] := LWorkers[LIndex].WaitExitCode;
    LWorkers[LIndex].Free;
    if LCodes[LIndex] = 0 then
      Inc(LWinners)
    else if LCodes[LIndex] = 10 then
      Inc(LRefused);
  end;
  Assert.AreEqual(1, LWinners, 'Exatamente um processo reserva');
  Assert.AreEqual(3, LRefused, 'Os demais recebem estoque insuficiente');
  Assert.AreEqual('1/1', LEnv.Balance(LProduct, LWarehouse));
end;

procedure TStockIntegrationTests.OrdersLockingInOppositeLineOrderDoNotDeadlock;
var
  LOutcomes: TThreadOutcomes;
begin
  FEnv := NewTestEnv;
  try
    FProductA := FEnv.NewProduct('1,00');
    FProductB := FEnv.NewProduct('1,00');
    FWarehouseA := FEnv.NewWarehouse;
    FEnv.AddStock(FProductA, FWarehouseA, '100');
    FEnv.AddStock(FProductB, FWarehouseA, '100');
    { Clientes diferentes: o bloqueio de cliente não pode mascarar o de saldo. }
    FCustomers[0] := FEnv.NewCustomer;
    FCustomers[1] := FEnv.NewCustomer;
    LOutcomes := RunConcurrently(FEnv, 2, ConfirmOppositeOrder);
    Assert.AreEqual(2, CountOutcome(LOutcomes, ''), 'Nenhum deadlock em 30 confirmações cruzadas');
    Assert.AreEqual('100/30', FEnv.Balance(FProductA, FWarehouseA));
    Assert.AreEqual('100/30', FEnv.Balance(FProductB, FWarehouseA));
  finally
    FEnv := nil;
  end;
end;

procedure TStockIntegrationTests.TransfersInOppositeDirectionsDoNotDeadlock;
var
  LOutcomes: TThreadOutcomes;
begin
  FEnv := NewTestEnv;
  try
    FProductA := FEnv.NewProduct('1,00');
    FWarehouseA := FEnv.NewWarehouse;
    FWarehouseB := FEnv.NewWarehouse;
    FEnv.AddStock(FProductA, FWarehouseA, '50');
    FEnv.AddStock(FProductA, FWarehouseB, '50');
    LOutcomes := RunConcurrently(FEnv, 2, TransferOppositeDirection);
    Assert.AreEqual(2, CountOutcome(LOutcomes, ''), 'Nenhum deadlock em 30 transferências cruzadas');
    Assert.AreEqual('50/0', FEnv.Balance(FProductA, FWarehouseA));
    Assert.AreEqual('50/0', FEnv.Balance(FProductA, FWarehouseB));
  finally
    FEnv := nil;
  end;
end;

procedure TStockIntegrationTests.TransferMovesBothSidesAtomically;
var
  LEnv: ITestEnv;
  LProduct, LFrom, LTo, LTransfer: Int64;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LFrom := LEnv.NewWarehouse;
  LTo := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LFrom, '10');
  LTransfer := LEnv.App.Stock.Transfer(LProduct, LFrom, LTo, Quantity('4'), 'Reposição da filial');
  Assert.AreEqual('6/0', LEnv.Balance(LProduct, LFrom));
  Assert.AreEqual('4/0', LEnv.Balance(LProduct, LTo));
  Assert.AreEqual(2, LEnv.CountRows('SELECT id FROM stock_movements WHERE source_type = ''STOCK_TRANSFER'' AND source_id = :id', [P('id', LTransfer)]));
end;

procedure TStockIntegrationTests.FailedTransferChangesNothing;
var
  LEnv: ITestEnv;
  LProduct, LFrom, LTo: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LFrom := LEnv.NewWarehouse;
  LTo := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LFrom, '3');
  LRaised := '';
  try
    LEnv.App.Stock.Transfer(LProduct, LFrom, LTo, Quantity('4'), 'Sem saldo');
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EInsufficientStock', LRaised);
  Assert.AreEqual('3/0', LEnv.Balance(LProduct, LFrom));
  Assert.AreEqual('sem saldo', LEnv.Balance(LProduct, LTo));
  Assert.AreEqual(0, LEnv.CountRows('SELECT id FROM stock_transfers WHERE product_id = :p', [P('p', LProduct)]));
end;

procedure TStockIntegrationTests.AdjustmentRequiresApprovalFromAnotherUser;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LAdjustment: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '10');
  LAdjustment := LEnv.App.Stock.RequestAdjustment(LProduct, LWarehouse, Quantity('8'), 'Contagem semestral');
  Assert.AreEqual('10/0', LEnv.Balance(LProduct, LWarehouse), 'Pedir ajuste não altera saldo');
  LRaised := '';
  try
    LEnv.App.Stock.ApproveAdjustment(LAdjustment);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('ESegregationOfDuties', LRaised);
  Assert.AreEqual('10/0', LEnv.Balance(LProduct, LWarehouse));
end;

procedure TStockIntegrationTests.ApprovedAdjustmentEntersKardexWithJustification;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LAdjustment: Int64;
  LApprover: TAppServices;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '10');
  LAdjustment := LEnv.App.Stock.RequestAdjustment(LProduct, LWarehouse, Quantity('8'), 'Contagem semestral');
  LApprover := LEnv.NewApp(LEnv.NewUser([PermStockAdjustApprove]));
  try
    LApprover.Stock.ApproveAdjustment(LAdjustment);
    Assert.AreEqual('8/0', LEnv.Balance(LProduct, LWarehouse));
    Assert.AreEqual('Contagem semestral', LEnv.QueryText(
      'SELECT reason FROM stock_movements WHERE source_type = ''STOCK_ADJUSTMENT'' AND source_id = :id', [P('id', LAdjustment)]));
    LRaised := '';
    try
      LApprover.Stock.ApproveAdjustment(LAdjustment);
    except
      on E: Exception do
        LRaised := E.ClassName;
    end;
    Assert.AreEqual('EInvalidTransition', LRaised, 'Ajuste decidido não pode ser aplicado de novo');
    Assert.AreEqual('8/0', LEnv.Balance(LProduct, LWarehouse));
  finally
    LApprover.Free;
  end;
end;

procedure TStockIntegrationTests.DatabaseRefusesNegativeBalanceFromDirectSql;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '1');
  LRaised := '';
  try
    LEnv.ExecuteSql('UPDATE stock_balances SET on_hand = -1 WHERE product_id = :p', [P('p', LProduct)]);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EIntegrityViolation', LRaised, 'Negativo');
  LRaised := '';
  try
    LEnv.ExecuteSql('UPDATE stock_balances SET reserved = 2 WHERE product_id = :p', [P('p', LProduct)]);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EIntegrityViolation', LRaised, 'Reservado acima do físico');
end;

procedure TStockIntegrationTests.DatabaseRefusesEditingKardex;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '1');
  LRaised := '';
  try
    LEnv.ExecuteSql('UPDATE stock_movements SET reason = ''x'' WHERE product_id = :p', [P('p', LProduct)]);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EIntegrityViolation', LRaised, 'UPDATE');
  LRaised := '';
  try
    LEnv.ExecuteSql('DELETE FROM stock_movements WHERE product_id = :p', [P('p', LProduct)]);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EIntegrityViolation', LRaised, 'DELETE');
end;

procedure TStockIntegrationTests.DatabaseRefusesReopeningClosedReservation;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '1');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '1')], LEnv.Key)).OrderId;
  LEnv.App.Sales.Cancel(LOrder, 'Desistiu');
  LRaised := '';
  try
    LEnv.ExecuteSql('UPDATE stock_reservations SET status = ''ACTIVE'' WHERE sales_order_id = :o', [P('o', LOrder)]);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EIntegrityViolation', LRaised);
end;

procedure TStockIntegrationTests.ClosingReservationTwiceReportsTheSecondAttempt;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LReservations: TReservationArray;
  LFirst, LSecond: Boolean;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '1');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '1')], LEnv.Key)).OrderId;
  LEnv.App.Uow.StartTransaction;
  try
    LReservations := LEnv.App.Uow.Stock.ReservationsOfOrder(LOrder);
    LFirst := LEnv.App.Uow.Stock.CloseReservation(LReservations[0].Id, rsReleased);
    LSecond := LEnv.App.Uow.Stock.CloseReservation(LReservations[0].Id, rsReleased);
  finally
    LEnv.App.Uow.Rollback;
  end;
  Assert.IsTrue(LFirst, 'Fecha a reserva ativa');
  Assert.IsFalse(LSecond, 'A segunda tentativa não fecha: é o que impede liberar duas vezes');
end;

procedure TStockIntegrationTests.BalancesReconcileWithKardex;
var
  LEnv: ITestEnv;
  LProduct, LFrom, LTo, LOrder: Int64;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LFrom := LEnv.NewWarehouse;
  LTo := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LFrom, '20');
  LEnv.App.Stock.Transfer(LProduct, LFrom, LTo, Quantity('5'), 'Reposição');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LFrom, '3')], LEnv.Key)).OrderId;
  LEnv.App.Sales.Cancel(LOrder, 'Desistiu');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LTo, '2')], LEnv.Key)).OrderId;
  LEnv.App.Sales.StartPicking(LOrder);
  LEnv.App.Sales.Ship(LOrder, 0);
  LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  Assert.AreEqual('15/0', LEnv.Balance(LProduct, LFrom));
  Assert.AreEqual('3/0', LEnv.Balance(LProduct, LTo));
  { Global de propósito: vale para tudo o que a suíte inteira gravou até aqui. }
  Assert.AreEqual(0, Length(LEnv.App.ReadModel.StockReconciliation.Rows), 'Saldo e soma do Kardex devem coincidir');
end;

procedure TStockIntegrationTests.MovementRecordsWhoWhyAndSourceDocument;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LUserId: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '2');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '2')], LEnv.Key)).OrderId;
  LUserId := LEnv.QueryText('SELECT user_id FROM stock_movements WHERE product_id = :p AND movement_type = ''RESERVE''', [P('p', LProduct)]);
  Assert.AreEqual(IntToStr(LEnv.App.Context.UserId), LUserId);
  Assert.AreEqual('SALES_ORDER', LEnv.QueryText('SELECT source_type FROM stock_movements WHERE product_id = :p AND movement_type = ''RESERVE''', [P('p', LProduct)]));
  Assert.AreEqual(IntToStr(LOrder), LEnv.QueryText('SELECT source_id FROM stock_movements WHERE product_id = :p AND movement_type = ''RESERVE''', [P('p', LProduct)]));
  Assert.IsTrue(LEnv.QueryText('SELECT reason FROM stock_movements WHERE product_id = :p AND movement_type = ''RESERVE''', [P('p', LProduct)]) <> '');
  Assert.IsTrue(LEnv.QueryText('SELECT correlation_id FROM stock_movements WHERE product_id = :p AND movement_type = ''RESERVE''', [P('p', LProduct)]) <> '');
end;

function PurchaseOf(const AEnv: ITestEnv; const AProduct, AWarehouse: Int64; const AQuantity: string; out AItemId: Int64): Int64;
var
  LLines: TPurchaseLineInputs;
begin
  SetLength(LLines, 1);
  LLines[0].ProductId := AProduct;
  LLines[0].Quantity := Quantity(AQuantity);
  LLines[0].UnitCost := TMoney.Parse('2,50');
  Result := AEnv.App.Purchases.CreateOrder(AEnv.NewSupplier, AWarehouse, LLines, '');
  AItemId := StrToInt64(AEnv.QueryText('SELECT id FROM purchase_order_items WHERE purchase_order_id = :id', [P('id', Result)]));
end;

function ReceiptLine(const AItemId: Int64; const AQuantity, ANote: string): TReceiptLineInputs;
begin
  SetLength(Result, 1);
  Result[0].ItemId := AItemId;
  Result[0].Quantity := Quantity(AQuantity);
  Result[0].Note := ANote;
end;

procedure TStockIntegrationTests.PartialReceiptThenCompletion;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder, LItem: Int64;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LOrder := PurchaseOf(LEnv, LProduct, LWarehouse, '10', LItem);
  LEnv.App.Purchases.Receive(LOrder, ReceiptLine(LItem, '4', ''), LEnv.Key, 'Primeira carga');
  Assert.AreEqual('4/0', LEnv.Balance(LProduct, LWarehouse));
  Assert.AreEqual('PARTIALLY_RECEIVED', LEnv.QueryText('SELECT status FROM purchase_orders WHERE id = :id', [P('id', LOrder)]));
  LEnv.App.Purchases.Receive(LOrder, ReceiptLine(LItem, '6', ''), LEnv.Key, 'Segunda carga');
  Assert.AreEqual('10/0', LEnv.Balance(LProduct, LWarehouse));
  Assert.AreEqual('RECEIVED', LEnv.QueryText('SELECT status FROM purchase_orders WHERE id = :id', [P('id', LOrder)]));
  Assert.AreEqual(2, LEnv.CountRows('SELECT id FROM stock_movements WHERE product_id = :p AND source_type = ''PURCHASE_RECEIPT''', [P('p', LProduct)]));
end;

procedure TStockIntegrationTests.RepeatedReceiptKeyDoesNotAddStockTwice;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder, LItem: Int64;
  LKey: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LOrder := PurchaseOf(LEnv, LProduct, LWarehouse, '10', LItem);
  LKey := LEnv.Key;
  Assert.IsTrue(LEnv.App.Purchases.Receive(LOrder, ReceiptLine(LItem, '4', ''), LKey, ''));
  Assert.IsFalse(LEnv.App.Purchases.Receive(LOrder, ReceiptLine(LItem, '4', ''), LKey, ''), 'Segunda chamada é repetição');
  Assert.AreEqual('4/0', LEnv.Balance(LProduct, LWarehouse));
end;

procedure TStockIntegrationTests.OverReceiptRequiresNoteAndAppearsAsDivergence;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder, LItem: Int64;
  LRaised: string;
  LTable: TDataTable;
  LRow: Integer;
  LFound: Boolean;
  LSku: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LOrder := PurchaseOf(LEnv, LProduct, LWarehouse, '10', LItem);
  LRaised := '';
  try
    LEnv.App.Purchases.Receive(LOrder, ReceiptLine(LItem, '12', ''), LEnv.Key, '');
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EValidationError', LRaised);
  Assert.AreEqual('sem saldo', LEnv.Balance(LProduct, LWarehouse), 'Rollback do recebimento recusado');
  LEnv.App.Purchases.Receive(LOrder, ReceiptLine(LItem, '12', 'Fornecedor enviou a mais'), LEnv.Key, '');
  Assert.AreEqual('12/0', LEnv.Balance(LProduct, LWarehouse));
  LSku := LEnv.QueryText('SELECT sku FROM products WHERE id = :id', [P('id', LProduct)]);
  LTable := LEnv.App.ReadModel.PurchaseDivergences;
  LFound := False;
  for LRow := 0 to High(LTable.Rows) do
    if LTable.Cell(LRow, 'SKU') = LSku then
    begin
      LFound := True;
      Assert.AreEqual('2', LTable.Cell(LRow, 'Divergência'));
    end;
  Assert.IsTrue(LFound, 'Excesso aparece no relatório');
end;

procedure TStockIntegrationTests.ClosingShortAppearsAsDivergence;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder, LItem: Int64;
  LTable: TDataTable;
  LRow: Integer;
  LFound: Boolean;
  LSku, LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('1,00');
  LWarehouse := LEnv.NewWarehouse;
  LOrder := PurchaseOf(LEnv, LProduct, LWarehouse, '10', LItem);
  LEnv.App.Purchases.Receive(LOrder, ReceiptLine(LItem, '7', ''), LEnv.Key, '');
  LEnv.App.Purchases.CloseShort(LOrder, 'Fornecedor sem estoque');
  LSku := LEnv.QueryText('SELECT sku FROM products WHERE id = :id', [P('id', LProduct)]);
  LTable := LEnv.App.ReadModel.PurchaseDivergences;
  LFound := False;
  for LRow := 0 to High(LTable.Rows) do
    if LTable.Cell(LRow, 'SKU') = LSku then
    begin
      LFound := True;
      Assert.AreEqual('-3', LTable.Cell(LRow, 'Divergência'));
    end;
  Assert.IsTrue(LFound, 'Falta aparece no relatório');
  LRaised := '';
  try
    LEnv.App.Purchases.Receive(LOrder, ReceiptLine(LItem, '3', ''), LEnv.Key, '');
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EInvalidTransition', LRaised, 'Pedido encerrado não recebe mais');
end;

initialization
  TDUnitX.RegisterTestFixture(TStockIntegrationTests);

end.
