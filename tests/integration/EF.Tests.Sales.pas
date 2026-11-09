unit EF.Tests.Sales;

{$I EF.inc}
{$M+}

interface

uses
  SysUtils, DUnitX.TestFramework,
  EF.Infrastructure.Composition, EF.Tests.Support;

type
  TSalesIntegrationTests = class(TObject)
  private
    FProduct, FWarehouse, FCustomer, FOrder: Int64;
    FProducts: array [0 .. 5] of Int64;
    FKey: string;
    procedure ConfirmSameKey(const AApp: TAppServices; const AIndex: Integer);
    procedure ConfirmWithinLimit(const AApp: TAppServices; const AIndex: Integer);
    procedure CancelOrder(const AApp: TAppServices; const AIndex: Integer);
  published
    procedure FullLifecycleRecordsEveryStatus;
    procedure RepeatingConfirmationDoesNotCreateAnotherOrder;
    procedure ConcurrentConfirmationsWithSameKeyCreateOneOrder;
    procedure ConfirmingDraftTwiceReservesOnce;
    procedure ConfirmationWithoutAvailabilityFails;
    procedure CancellingReleasesReservationExactlyOnce;
    procedure ConcurrentCancellationsReleaseOnce;
    procedure CannotCancelAfterPicking;
    procedure CannotInvoiceCancelledOrder;
    procedure CannotInvoiceBeforeShipping;
    procedure FailureWritingMovementRollsEverythingBack;
    procedure BalancesAreLockedInAscendingOrderWhateverTheInputOrder;
    procedure CreditLimitIsEnforced;
    procedure ConcurrentOrdersCannotExceedCreditLimit;
    procedure FractionRefusedForUnitAndAcceptedForMeter;
    procedure DuplicateLineIsRefused;
    procedure PriceComesFromCatalogNotFromCaller;
    procedure MissingPermissionIsRefusedBeforeAnyWrite;
    procedure DatabaseKeepsInvoicedOrderTerminal;
    procedure OperationWritesAuditEvent;
  end;

implementation

uses
  EF.Application.Ports, EF.Domain.Exceptions, EF.Domain.Stock, EF.Domain.Money, EF.Domain.Quantity,
  EF.Application.Sales,
  EF.Infrastructure.Database, EF.Infrastructure.UnitOfWork, EF.Shared.Logging, EF.Shared.Text,
  EF.Tests.Faults;

procedure TSalesIntegrationTests.ConfirmSameKey(const AApp: TAppServices; const AIndex: Integer);
begin
  AApp.Sales.ConfirmNew(OrderCommand(FCustomer, [Line(FProduct, FWarehouse, '1')], FKey));
end;

procedure TSalesIntegrationTests.ConfirmWithinLimit(const AApp: TAppServices; const AIndex: Integer);
begin
  AApp.Sales.ConfirmNew(OrderCommand(FCustomer, [Line(FProducts[AIndex], FWarehouse, '1')], NewCorrelationId));
end;

procedure TSalesIntegrationTests.CancelOrder(const AApp: TAppServices; const AIndex: Integer);
begin
  AApp.Sales.Cancel(FOrder, 'Concorrente ' + IntToStr(AIndex));
end;

procedure TSalesIntegrationTests.FullLifecycleRecordsEveryStatus;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LCommand: TNewOrderCommand;
  LHistory: TDataTable;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('12,50');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '10');
  LCommand := OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '4')], '');
  LOrder := LEnv.App.Sales.CreateDraft(LCommand);
  Assert.AreEqual('10/0', LEnv.Balance(LProduct, LWarehouse), 'Orçamento não reserva');
  LEnv.App.Sales.ConfirmDraft(LOrder, LEnv.Key);
  Assert.AreEqual('10/4', LEnv.Balance(LProduct, LWarehouse));
  LEnv.App.Sales.StartPicking(LOrder);
  LEnv.App.Sales.Ship(LOrder, 0);
  LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  Assert.AreEqual('6/0', LEnv.Balance(LProduct, LWarehouse));
  LHistory := LEnv.App.ReadModel.SalesOrderHistory(LOrder);
  Assert.AreEqual(6, Length(LHistory.Rows));
  Assert.AreEqual('DRAFT', LHistory.Cell(0, 'Para'));
  Assert.AreEqual('CONFIRMED', LHistory.Cell(1, 'Para'));
  Assert.AreEqual('RESERVED', LHistory.Cell(2, 'Para'));
  Assert.AreEqual('PICKING', LHistory.Cell(3, 'Para'));
  Assert.AreEqual('SHIPPED', LHistory.Cell(4, 'Para'));
  Assert.AreEqual('INVOICED', LHistory.Cell(5, 'Para'));
end;

procedure TSalesIntegrationTests.RepeatingConfirmationDoesNotCreateAnotherOrder;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LCustomer: Int64;
  LKey: string;
  LFirst, LSecond: TConfirmResult;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LCustomer := LEnv.NewCustomer;
  LEnv.AddStock(LProduct, LWarehouse, '10');
  LKey := LEnv.Key;
  LFirst := LEnv.App.Sales.ConfirmNew(OrderCommand(LCustomer, [Line(LProduct, LWarehouse, '2')], LKey));
  LSecond := LEnv.App.Sales.ConfirmNew(OrderCommand(LCustomer, [Line(LProduct, LWarehouse, '2')], LKey));
  Assert.IsFalse(LFirst.AlreadyProcessed);
  Assert.IsTrue(LSecond.AlreadyProcessed);
  Assert.AreEqual(IntToStr(LFirst.OrderId), IntToStr(LSecond.OrderId));
  Assert.AreEqual('10/2', LEnv.Balance(LProduct, LWarehouse));
  Assert.AreEqual(1, LEnv.CountRows('SELECT id FROM stock_reservations WHERE product_id = :p', [P('p', LProduct)]));
end;

procedure TSalesIntegrationTests.ConcurrentConfirmationsWithSameKeyCreateOneOrder;
var
  LEnv: ITestEnv;
  LOutcomes: TThreadOutcomes;
begin
  LEnv := NewTestEnv;
  FProduct := LEnv.NewProduct('10,00');
  FWarehouse := LEnv.NewWarehouse;
  FCustomer := LEnv.NewCustomer;
  LEnv.AddStock(FProduct, FWarehouse, '10');
  FKey := LEnv.Key;
  LOutcomes := RunConcurrently(LEnv, 6, ConfirmSameKey);
  Assert.AreEqual(6, CountOutcome(LOutcomes, ''), 'Todos recebem o mesmo pedido, sem erro: ' + DescribeOutcomes(LOutcomes));
  Assert.AreEqual(1, LEnv.CountRows('SELECT id FROM sales_orders WHERE idempotency_key = :k', [P('k', FKey)]));
  Assert.AreEqual('10/1', LEnv.Balance(FProduct, FWarehouse));
end;

procedure TSalesIntegrationTests.ConfirmingDraftTwiceReservesOnce;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LSecond: TConfirmResult;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '10');
  LOrder := LEnv.App.Sales.CreateDraft(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '3')], ''));
  LEnv.App.Sales.ConfirmDraft(LOrder, '');
  LSecond := LEnv.App.Sales.ConfirmDraft(LOrder, '');
  Assert.IsTrue(LSecond.AlreadyProcessed);
  Assert.AreEqual('10/3', LEnv.Balance(LProduct, LWarehouse));
end;

procedure TSalesIntegrationTests.ConfirmationWithoutAvailabilityFails;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LRaised, LMessage: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '1');
  LOrder := LEnv.App.Sales.CreateDraft(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '2')], ''));
  LRaised := '';
  LMessage := '';
  try
    LEnv.App.Sales.ConfirmDraft(LOrder, '');
  except
    on E: Exception do
    begin
      LRaised := E.ClassName;
      LMessage := E.Message;
    end;
  end;
  Assert.AreEqual('EInsufficientStock', LRaised);
  Assert.IsTrue(Pos('Disponível: 1', LMessage) > 0, 'A mensagem diz o que falta: ' + LMessage);
  Assert.AreEqual('DRAFT', LEnv.QueryText('SELECT status FROM sales_orders WHERE id = :id', [P('id', LOrder)]));
end;

procedure TSalesIntegrationTests.CancellingReleasesReservationExactlyOnce;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '5');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '2')], LEnv.Key)).OrderId;
  LEnv.App.Sales.Cancel(LOrder, 'Cliente desistiu');
  Assert.AreEqual('5/0', LEnv.Balance(LProduct, LWarehouse));
  Assert.AreEqual('RELEASED', LEnv.QueryText('SELECT status FROM stock_reservations WHERE sales_order_id = :o', [P('o', LOrder)]));
  LRaised := '';
  try
    LEnv.App.Sales.Cancel(LOrder, 'De novo');
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EInvalidTransition', LRaised);
  Assert.AreEqual('5/0', LEnv.Balance(LProduct, LWarehouse));
  Assert.AreEqual(1, LEnv.CountRows('SELECT id FROM stock_movements WHERE product_id = :p AND movement_type = ''RELEASE''', [P('p', LProduct)]));
end;

procedure TSalesIntegrationTests.ConcurrentCancellationsReleaseOnce;
var
  LEnv: ITestEnv;
  LOutcomes: TThreadOutcomes;
begin
  LEnv := NewTestEnv;
  FProduct := LEnv.NewProduct('10,00');
  FWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(FProduct, FWarehouse, '5');
  { Outra reserva ativa no mesmo saldo: liberar duas vezes não estouraria a CHECK. }
  LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(FProduct, FWarehouse, '2')], LEnv.Key));
  FOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(FProduct, FWarehouse, '2')], LEnv.Key)).OrderId;
  LOutcomes := RunConcurrently(LEnv, 5, CancelOrder);
  Assert.AreEqual(1, CountOutcome(LOutcomes, ''), 'Um cancela');
  Assert.AreEqual(4, CountOutcome(LOutcomes, 'EInvalidTransition'), 'Os outros veem o pedido já cancelado: ' + DescribeOutcomes(LOutcomes));
  Assert.AreEqual('5/2', LEnv.Balance(FProduct, FWarehouse), 'Só a reserva deste pedido volta, e uma vez');
end;

procedure TSalesIntegrationTests.CannotCancelAfterPicking;
var
  LEnv: ITestEnv;
  LOrder: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LOrder := ShippedOrder(LEnv, '10,00');
  LRaised := '';
  try
    LEnv.App.Sales.Cancel(LOrder, 'Tarde demais');
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EInvalidTransition', LRaised);
end;

procedure TSalesIntegrationTests.CannotInvoiceCancelledOrder;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '5');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '1')], LEnv.Key)).OrderId;
  LEnv.App.Sales.Cancel(LOrder, 'Desistiu');
  LRaised := '';
  try
    LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EInvalidTransition', LRaised);
  Assert.AreEqual(0, LEnv.CountRows('SELECT id FROM invoices WHERE sales_order_id = :o', [P('o', LOrder)]));
end;

procedure TSalesIntegrationTests.CannotInvoiceBeforeShipping;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '5');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '1')], LEnv.Key)).OrderId;
  LRaised := '';
  try
    LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EInvalidTransition', LRaised);
  Assert.AreEqual('5/1', LEnv.Balance(LProduct, LWarehouse));
end;

procedure TSalesIntegrationTests.FailureWritingMovementRollsEverythingBack;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse: Int64;
  LUow: IUnitOfWork;
  LService: TSalesService;
  LKey, LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '5');
  LKey := LEnv.Key;
  LUow := TFailingUnitOfWork.Create(TUnitOfWork.Create(LEnv.App.Session), mtReserve);
  LService := TSalesService.Create(LUow, LEnv.App.Context, TSystemClock.Create, TNullLogger.Create);
  try
    LRaised := '';
    try
      LService.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '1')], LKey));
    except
      on E: Exception do
        LRaised := E.ClassName;
    end;
  finally
    LService.Free;
  end;
  Assert.AreEqual('EInjectedFault', LRaised);
  Assert.AreEqual('5/0', LEnv.Balance(LProduct, LWarehouse), 'Saldo já alterado na transação volta');
  Assert.AreEqual(0, LEnv.CountRows('SELECT id FROM sales_orders WHERE idempotency_key = :k', [P('k', LKey)]), 'Pedido já inserido some');
  Assert.AreEqual(0, LEnv.CountRows('SELECT id FROM stock_reservations WHERE product_id = :p', [P('p', LProduct)]));
end;

procedure TSalesIntegrationTests.BalancesAreLockedInAscendingOrderWhateverTheInputOrder;
var
  LEnv: ITestEnv;
  LFirst, LSecond, LThird, LWarehouseA, LWarehouseB: Int64;
  LRepository: TFailingStockRepository;
  LStock: IStockRepository;
  LInner, LUow: IUnitOfWork;
  LService: TSalesService;
  LIndex: Integer;
begin
  { O teste de estresse depende de as threads colidirem. Este prova a regra diretamente. }
  LEnv := NewTestEnv;
  LFirst := LEnv.NewProduct('1,00');
  LSecond := LEnv.NewProduct('1,00');
  LThird := LEnv.NewProduct('1,00');
  LWarehouseA := LEnv.NewWarehouse;
  LWarehouseB := LEnv.NewWarehouse;
  LEnv.AddStock(LFirst, LWarehouseA, '5');
  LEnv.AddStock(LFirst, LWarehouseB, '5');
  LEnv.AddStock(LSecond, LWarehouseA, '5');
  LEnv.AddStock(LThird, LWarehouseA, '5');
  LInner := TUnitOfWork.Create(LEnv.App.Session);
  LRepository := TFailingStockRepository.CreateRecording(LInner.Stock);
  LStock := LRepository;
  LUow := TFailingUnitOfWork.CreateWith(LInner, LStock);
  LService := TSalesService.Create(LUow, LEnv.App.Context, TSystemClock.Create, TNullLogger.Create);
  try
    LService.ConfirmNew(OrderCommand(LEnv.NewCustomer,
      [Line(LThird, LWarehouseA, '1'), Line(LFirst, LWarehouseB, '1'), Line(LSecond, LWarehouseA, '1'), Line(LFirst, LWarehouseA, '1')], LEnv.Key));
  finally
    LService.Free;
  end;
  { Validação (4 bloqueios) e depois reserva (mesmas linhas, já em posse da transação). }
  Assert.AreEqual(8, Length(LRepository.Locks));
  Assert.AreEqual(IntToStr(LFirst), IntToStr(LRepository.Locks[0].ProductId), 'Menor produto primeiro, não o primeiro item digitado');
  Assert.AreEqual(IntToStr(LWarehouseA), IntToStr(LRepository.Locks[0].WarehouseId));
  for LIndex := 1 to 3 do
    Assert.IsTrue(
      (LRepository.Locks[LIndex].ProductId > LRepository.Locks[LIndex - 1].ProductId) or
      ((LRepository.Locks[LIndex].ProductId = LRepository.Locks[LIndex - 1].ProductId) and (LRepository.Locks[LIndex].WarehouseId > LRepository.Locks[LIndex - 1].WarehouseId)),
      Format('Bloqueio fora de ordem na posição %d', [LIndex]));
  for LIndex := 4 to 7 do
    Assert.AreEqual(IntToStr(LRepository.Locks[LIndex - 4].ProductId), IntToStr(LRepository.Locks[LIndex].ProductId), 'Reserva segue a mesma ordem');
end;

procedure TSalesIntegrationTests.CreditLimitIsEnforced;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LCustomer: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('100,00');
  LWarehouse := LEnv.NewWarehouse;
  LCustomer := LEnv.NewCustomer('250,00');
  LEnv.AddStock(LProduct, LWarehouse, '10');
  LEnv.App.Sales.ConfirmNew(OrderCommand(LCustomer, [Line(LProduct, LWarehouse, '2')], LEnv.Key));
  LRaised := '';
  try
    LEnv.App.Sales.ConfirmNew(OrderCommand(LCustomer, [Line(LProduct, LWarehouse, '1')], LEnv.Key));
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('ECreditLimitExceeded', LRaised, '200 reservados + 100 passam de 250');
  Assert.AreEqual('10/2', LEnv.Balance(LProduct, LWarehouse));
end;

procedure TSalesIntegrationTests.ConcurrentOrdersCannotExceedCreditLimit;
var
  LEnv: ITestEnv;
  LOutcomes: TThreadOutcomes;
  LIndex: Integer;
begin
  LEnv := NewTestEnv;
  FWarehouse := LEnv.NewWarehouse;
  FCustomer := LEnv.NewCustomer('100,00');
  { Um produto por thread: só o bloqueio do cliente serializa estas vendas. Com produto
    único, o bloqueio do saldo esconderia a falta dele. }
  for LIndex := 0 to High(FProducts) do
  begin
    FProducts[LIndex] := LEnv.NewProduct('100,00');
    LEnv.AddStock(FProducts[LIndex], FWarehouse, '5');
  end;
  LOutcomes := RunConcurrently(LEnv, Length(FProducts), ConfirmWithinLimit);
  Assert.AreEqual(1, CountOutcome(LOutcomes, ''), 'Só uma venda cabe no limite: ' + DescribeOutcomes(LOutcomes));
  Assert.AreEqual(5, CountOutcome(LOutcomes, 'ECreditLimitExceeded'));
end;

procedure TSalesIntegrationTests.FractionRefusedForUnitAndAcceptedForMeter;
var
  LEnv: ITestEnv;
  LUnit, LMeter, LWarehouse: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LUnit := LEnv.NewProduct('10,00');
  LMeter := LEnv.NewProduct('10,00', True);
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LUnit, LWarehouse, '5');
  LEnv.AddStock(LMeter, LWarehouse, '5');
  LRaised := '';
  try
    LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LUnit, LWarehouse, '1,5')], LEnv.Key));
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EValidationError', LRaised);
  LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LMeter, LWarehouse, '1,5')], LEnv.Key));
  Assert.AreEqual('5/1,5', LEnv.Balance(LMeter, LWarehouse));
end;

procedure TSalesIntegrationTests.DuplicateLineIsRefused;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '5');
  LRaised := '';
  try
    LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '1'), Line(LProduct, LWarehouse, '1')], LEnv.Key));
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EValidationError', LRaised);
end;

procedure TSalesIntegrationTests.PriceComesFromCatalogNotFromCaller;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('3,33', True);
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '5');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '1,5')], LEnv.Key)).OrderId;
  { 3,33 x 1,5 = 4,995 -> 5,00: gravado como NUMERIC, sem resíduo de ponto flutuante. }
  Assert.AreEqual('5.00', LEnv.QueryMoney('SELECT total FROM sales_orders WHERE id = :id', [P('id', LOrder)]));
end;

procedure TSalesIntegrationTests.MissingPermissionIsRefusedBeforeAnyWrite;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LCustomer: Int64;
  LRestricted: TAppServices;
  LKey, LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LCustomer := LEnv.NewCustomer;
  LEnv.AddStock(LProduct, LWarehouse, '5');
  LKey := LEnv.Key;
  LRestricted := LEnv.NewApp(LEnv.NewUser([PermReportsView]));
  try
    LRaised := '';
    try
      LRestricted.Sales.ConfirmNew(OrderCommand(LCustomer, [Line(LProduct, LWarehouse, '1')], LKey));
    except
      on E: Exception do
        LRaised := E.ClassName;
    end;
  finally
    LRestricted.Free;
  end;
  Assert.AreEqual('EPermissionDenied', LRaised);
  Assert.AreEqual('5/0', LEnv.Balance(LProduct, LWarehouse));
end;

procedure TSalesIntegrationTests.DatabaseKeepsInvoicedOrderTerminal;
var
  LEnv: ITestEnv;
  LOrder: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LOrder := ShippedOrder(LEnv, '10,00');
  LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  LRaised := '';
  try
    LEnv.ExecuteSql('UPDATE sales_orders SET status = ''DRAFT'' WHERE id = :id', [P('id', LOrder)]);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EIntegrityViolation', LRaised, 'Nem SQL direto volta pedido faturado para orçamento');
end;

procedure TSalesIntegrationTests.OperationWritesAuditEvent;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LCorrelation: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('10,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '5');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '1')], LEnv.Key)).OrderId;
  Assert.AreEqual(1, LEnv.CountRows('SELECT id FROM audit_events WHERE action = ''order.confirmed'' AND entity_id = :id', [P('id', LOrder)]));
  LCorrelation := LEnv.QueryText('SELECT correlation_id FROM audit_events WHERE action = ''order.confirmed'' AND entity_id = :id', [P('id', LOrder)]);
  Assert.AreEqual(LCorrelation, LEnv.QueryText('SELECT correlation_id FROM stock_movements WHERE product_id = :p AND movement_type = ''RESERVE''', [P('p', LProduct)]),
    'Auditoria e Kardex compartilham a correlação da operação');
end;

initialization
  TDUnitX.RegisterTestFixture(TSalesIntegrationTests);

end.
