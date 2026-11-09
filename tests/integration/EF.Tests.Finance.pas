unit EF.Tests.Finance;

{$I EF.inc}
{$M+}

interface

uses
  SysUtils, DUnitX.TestFramework,
  EF.Infrastructure.Composition, EF.Tests.Support;

type
  TFinanceIntegrationTests = class(TObject)
  private
    FInstallment, FSettlement: Int64;
    procedure SettleSeventy(const AApp: TAppServices; const AIndex: Integer);
    procedure ReverseSettlement(const AApp: TAppServices; const AIndex: Integer);
  published
    procedure InvoiceConvertsReservationAndCreatesReceivable;
    procedure RepeatingInvoiceDoesNotDuplicate;
    procedure FailureDuringInvoiceRollsEverythingBack;
    procedure InvoiceEnqueuesOutboxEventInSameTransaction;
    procedure InstallmentsSumExactlyToTotal;
    procedure PartialSettlementUpdatesBalanceAndStatus;
    procedure FullSettlementMarksTitlePaid;
    procedure PaymentAboveOutstandingIsRefused;
    procedure RepeatedSettlementKeyDoesNotPayTwice;
    procedure ConcurrentSettlementsCannotOverpay;
    procedure ReversalKeepsOriginalAndAddsCompensatingRow;
    procedure ReversalCanHappenOnlyOnce;
    procedure ConcurrentReversalsApplyOnce;
    procedure ReversalOfAReversalIsRefused;
    procedure DatabaseRefusesOverpaymentAndEditingSettlement;
    procedure OverdueIsDerivedFromTheDate;
    procedure SuggestedChargesFollowConfiguredPolicy;
    procedure CashFlowSeparatesForecastFromRealized;
    procedure TitleWithPaymentCannotBeCancelled;
    procedure PaidInvoicesFreeCreditLimit;
  end;

implementation

uses
  EF.Application.Ports, EF.Application.Finance, EF.Domain.Money, EF.Domain.Stock, EF.Domain.Policies,
  EF.Infrastructure.Database, EF.Infrastructure.UnitOfWork, EF.Shared.Logging, EF.Shared.Text,
  EF.Tests.Faults;

function Settlement(const AInstallment: Int64; const APrincipal, AKey: string; const ADiscount: string = '0'): TSettleCommand;
begin
  Result.InstallmentId := AInstallment;
  Result.Principal := TMoney.Parse(APrincipal);
  Result.Interest := TMoney.Zero;
  Result.Penalty := TMoney.Zero;
  Result.Discount := TMoney.Parse(ADiscount);
  Result.PaidOn := Date;
  Result.IdempotencyKey := AKey;
  Result.Note := '';
end;

function InvoicedInstallment(const AEnv: ITestEnv; const APrice: string; out AOrder: Int64): Int64;
begin
  AOrder := ShippedOrder(AEnv, APrice);
  AEnv.App.Invoicing.InvoiceOrder(AOrder, Date + 30);
  Result := FirstInstallmentOf(AEnv, AOrder);
end;

function TitleStatusOfOrder(const AEnv: ITestEnv; const AOrder: Int64): string;
begin
  Result := AEnv.QueryText(
    'SELECT t.status FROM receivable_titles t JOIN invoices n ON n.id = t.invoice_id WHERE n.sales_order_id = :o', [P('o', AOrder)]);
end;

procedure TFinanceIntegrationTests.SettleSeventy(const AApp: TAppServices; const AIndex: Integer);
begin
  AApp.Receivables.Settle(Settlement(FInstallment, '70,00', NewCorrelationId));
end;

procedure TFinanceIntegrationTests.ReverseSettlement(const AApp: TAppServices; const AIndex: Integer);
begin
  AApp.Receivables.Reverse(FSettlement, 'Cheque devolvido');
end;

procedure TFinanceIntegrationTests.InvoiceConvertsReservationAndCreatesReceivable;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LOrder: Int64;
  LResult: TInvoiceResult;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('50,00');
  LWarehouse := LEnv.NewWarehouse;
  LEnv.AddStock(LProduct, LWarehouse, '10');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LEnv.NewCustomer, [Line(LProduct, LWarehouse, '2')], LEnv.Key, 2)).OrderId;
  LEnv.App.Sales.StartPicking(LOrder);
  LEnv.App.Sales.Ship(LOrder, 0);
  LResult := LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  Assert.AreEqual('8/0', LEnv.Balance(LProduct, LWarehouse));
  Assert.AreEqual('CONSUMED', LEnv.QueryText('SELECT status FROM stock_reservations WHERE sales_order_id = :o', [P('o', LOrder)]));
  Assert.AreEqual('INVOICED', LEnv.QueryText('SELECT status FROM sales_orders WHERE id = :id', [P('id', LOrder)]));
  Assert.AreEqual('100.00', LEnv.QueryMoney('SELECT total FROM invoices WHERE id = :id', [P('id', LResult.InvoiceId)]));
  Assert.AreEqual(2, LEnv.CountRows(
    'SELECT i.id FROM receivable_installments i JOIN receivable_titles t ON t.id = i.title_id WHERE t.invoice_id = :id', [P('id', LResult.InvoiceId)]));
  Assert.AreEqual(1, LEnv.CountRows('SELECT id FROM stock_movements WHERE product_id = :p AND movement_type = ''ISSUE''', [P('p', LProduct)]));
end;

procedure TFinanceIntegrationTests.RepeatingInvoiceDoesNotDuplicate;
var
  LEnv: ITestEnv;
  LOrder: Int64;
  LFirst, LSecond: TInvoiceResult;
begin
  LEnv := NewTestEnv;
  LOrder := ShippedOrder(LEnv, '10,00');
  LFirst := LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  LSecond := LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  Assert.IsTrue(LSecond.AlreadyProcessed);
  Assert.AreEqual(IntToStr(LFirst.InvoiceId), IntToStr(LSecond.InvoiceId));
  Assert.AreEqual(1, LEnv.CountRows('SELECT id FROM invoices WHERE sales_order_id = :o', [P('o', LOrder)]));
end;

procedure TFinanceIntegrationTests.FailureDuringInvoiceRollsEverythingBack;
var
  LEnv: ITestEnv;
  LOrder: Int64;
  LUow: IUnitOfWork;
  LService: TInvoicingService;
  LRaised, LProductBalance: string;
  LProduct, LWarehouse: string;
begin
  LEnv := NewTestEnv;
  LOrder := ShippedOrder(LEnv, '10,00');
  LProduct := LEnv.QueryText('SELECT product_id FROM sales_order_items WHERE sales_order_id = :o', [P('o', LOrder)]);
  LWarehouse := LEnv.QueryText('SELECT warehouse_id FROM sales_order_items WHERE sales_order_id = :o', [P('o', LOrder)]);
  LProductBalance := LEnv.Balance(StrToInt64(LProduct), StrToInt64(LWarehouse));
  LUow := TFailingUnitOfWork.Create(TUnitOfWork.Create(LEnv.App.Session), mtIssue);
  LService := TInvoicingService.Create(LUow, LEnv.App.Context, TSystemClock.Create, TNullLogger.Create);
  try
    LRaised := '';
    try
      LService.InvoiceOrder(LOrder, Date + 30);
    except
      on E: Exception do
        LRaised := E.ClassName;
    end;
  finally
    LService.Free;
  end;
  Assert.AreEqual('EInjectedFault', LRaised);
  Assert.AreEqual('SHIPPED', LEnv.QueryText('SELECT status FROM sales_orders WHERE id = :id', [P('id', LOrder)]));
  Assert.AreEqual('ACTIVE', LEnv.QueryText('SELECT status FROM stock_reservations WHERE sales_order_id = :o', [P('o', LOrder)]));
  Assert.AreEqual(LProductBalance, LEnv.Balance(StrToInt64(LProduct), StrToInt64(LWarehouse)));
  Assert.AreEqual(0, LEnv.CountRows('SELECT id FROM invoices WHERE sales_order_id = :o', [P('o', LOrder)]));
  { O sucesso depois da falha prova que a reserva continuou utilizável. }
  LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  Assert.AreEqual('INVOICED', LEnv.QueryText('SELECT status FROM sales_orders WHERE id = :id', [P('id', LOrder)]));
end;

procedure TFinanceIntegrationTests.InvoiceEnqueuesOutboxEventInSameTransaction;
var
  LEnv: ITestEnv;
  LOrder: Int64;
  LResult: TInvoiceResult;
begin
  LEnv := NewTestEnv;
  LOrder := ShippedOrder(LEnv, '10,00');
  LResult := LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  Assert.AreEqual('PENDING', LEnv.QueryText('SELECT status FROM outbox_events WHERE aggregate_id = :id AND event_type = ''invoice.issued''', [P('id', LResult.InvoiceId)]));
  Assert.AreEqual('invoice-issued-' + IntToStr(LResult.InvoiceId),
    LEnv.QueryText('SELECT idempotency_key FROM outbox_events WHERE aggregate_id = :id AND event_type = ''invoice.issued''', [P('id', LResult.InvoiceId)]));
end;

procedure TFinanceIntegrationTests.InstallmentsSumExactlyToTotal;
var
  LEnv: ITestEnv;
  LOrder: Int64;
  LResult: TInvoiceResult;
begin
  LEnv := NewTestEnv;
  LOrder := ShippedOrder(LEnv, '100,00', 3);
  LResult := LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  Assert.AreEqual('100.00', LEnv.QueryMoney(
    'SELECT CAST(SUM(i.amount) AS NUMERIC(18,2)) FROM receivable_installments i JOIN receivable_titles t ON t.id = i.title_id WHERE t.invoice_id = :id', [P('id', LResult.InvoiceId)]));
  Assert.AreEqual('33.34', LEnv.QueryMoney(
    'SELECT i.amount FROM receivable_installments i JOIN receivable_titles t ON t.id = i.title_id WHERE t.invoice_id = :id AND i.installment_no = 1', [P('id', LResult.InvoiceId)]));
end;

procedure TFinanceIntegrationTests.PartialSettlementUpdatesBalanceAndStatus;
var
  LEnv: ITestEnv;
  LOrder, LInstallment: Int64;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LEnv.App.Receivables.Settle(Settlement(LInstallment, '30,00', LEnv.Key));
  Assert.AreEqual('30.00', LEnv.QueryMoney('SELECT principal_paid FROM receivable_installments WHERE id = :id', [P('id', LInstallment)]));
  Assert.AreEqual('PARTIALLY_PAID', TitleStatusOfOrder(LEnv, LOrder));
end;

procedure TFinanceIntegrationTests.FullSettlementMarksTitlePaid;
var
  LEnv: ITestEnv;
  LOrder, LInstallment: Int64;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LEnv.App.Receivables.Settle(Settlement(LInstallment, '30,00', LEnv.Key));
  LEnv.App.Receivables.Settle(Settlement(LInstallment, '65,00', LEnv.Key, '5,00'));
  Assert.AreEqual('PAID', TitleStatusOfOrder(LEnv, LOrder));
end;

procedure TFinanceIntegrationTests.PaymentAboveOutstandingIsRefused;
var
  LEnv: ITestEnv;
  LOrder, LInstallment: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LRaised := '';
  try
    LEnv.App.Receivables.Settle(Settlement(LInstallment, '100,01', LEnv.Key));
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EOverpayment', LRaised);
  Assert.AreEqual('OPEN', TitleStatusOfOrder(LEnv, LOrder));
end;

procedure TFinanceIntegrationTests.RepeatedSettlementKeyDoesNotPayTwice;
var
  LEnv: ITestEnv;
  LOrder, LInstallment: Int64;
  LKey: string;
  LSecond: TSettleResult;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LKey := LEnv.Key;
  LEnv.App.Receivables.Settle(Settlement(LInstallment, '30,00', LKey));
  LSecond := LEnv.App.Receivables.Settle(Settlement(LInstallment, '30,00', LKey));
  Assert.IsTrue(LSecond.AlreadyProcessed);
  Assert.AreEqual('30.00', LEnv.QueryMoney('SELECT principal_paid FROM receivable_installments WHERE id = :id', [P('id', LInstallment)]));
end;

procedure TFinanceIntegrationTests.ConcurrentSettlementsCannotOverpay;
var
  LEnv: ITestEnv;
  LOrder: Int64;
  LOutcomes: TThreadOutcomes;
begin
  LEnv := NewTestEnv;
  FInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LOutcomes := RunConcurrently(LEnv, 4, SettleSeventy);
  Assert.AreEqual(1, CountOutcome(LOutcomes, ''), 'Só um pagamento de 70 cabe em 100: ' + DescribeOutcomes(LOutcomes));
  Assert.AreEqual(3, CountOutcome(LOutcomes, 'EOverpayment'));
  Assert.AreEqual('70.00', LEnv.QueryMoney('SELECT principal_paid FROM receivable_installments WHERE id = :id', [P('id', FInstallment)]));
end;

procedure TFinanceIntegrationTests.ReversalKeepsOriginalAndAddsCompensatingRow;
var
  LEnv: ITestEnv;
  LOrder, LInstallment, LReversal: Int64;
  LOriginal: TSettleResult;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LOriginal := LEnv.App.Receivables.Settle(Settlement(LInstallment, '100,00', LEnv.Key));
  Assert.AreEqual('PAID', TitleStatusOfOrder(LEnv, LOrder));
  LReversal := LEnv.App.Receivables.Reverse(LOriginal.SettlementId, 'Cheque devolvido');
  Assert.AreEqual('100.00', LEnv.QueryMoney('SELECT principal FROM receivable_settlements WHERE id = :id', [P('id', LOriginal.SettlementId)]), 'Original intacta');
  Assert.AreEqual('-100.00', LEnv.QueryMoney('SELECT principal FROM receivable_settlements WHERE id = :id', [P('id', LReversal)]));
  Assert.AreEqual(IntToStr(LOriginal.SettlementId), LEnv.QueryText('SELECT reversal_of_id FROM receivable_settlements WHERE id = :id', [P('id', LReversal)]));
  Assert.AreEqual('0.00', LEnv.QueryMoney('SELECT principal_paid FROM receivable_installments WHERE id = :id', [P('id', LInstallment)]));
  Assert.AreEqual('OPEN', TitleStatusOfOrder(LEnv, LOrder));
  Assert.AreEqual(1, LEnv.CountRows('SELECT id FROM audit_events WHERE action = ''receivable.reversed'' AND entity_id = :id', [P('id', LInstallment)]));
end;

procedure TFinanceIntegrationTests.ReversalCanHappenOnlyOnce;
var
  LEnv: ITestEnv;
  LOrder, LInstallment: Int64;
  LOriginal: TSettleResult;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LOriginal := LEnv.App.Receivables.Settle(Settlement(LInstallment, '40,00', LEnv.Key));
  LEnv.App.Receivables.Reverse(LOriginal.SettlementId, 'Erro de digitação');
  LRaised := '';
  try
    LEnv.App.Receivables.Reverse(LOriginal.SettlementId, 'De novo');
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EAlreadyReversed', LRaised);
  Assert.AreEqual('0.00', LEnv.QueryMoney('SELECT principal_paid FROM receivable_installments WHERE id = :id', [P('id', LInstallment)]));
end;

procedure TFinanceIntegrationTests.ConcurrentReversalsApplyOnce;
var
  LEnv: ITestEnv;
  LOrder, LInstallment: Int64;
  LOutcomes: TThreadOutcomes;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  FSettlement := LEnv.App.Receivables.Settle(Settlement(LInstallment, '40,00', LEnv.Key)).SettlementId;
  LEnv.App.Receivables.Settle(Settlement(LInstallment, '10,00', LEnv.Key));
  LOutcomes := RunConcurrently(LEnv, 4, ReverseSettlement);
  Assert.AreEqual(1, CountOutcome(LOutcomes, ''));
  Assert.AreEqual(3, CountOutcome(LOutcomes, 'EAlreadyReversed'));
  Assert.AreEqual('10.00', LEnv.QueryMoney('SELECT principal_paid FROM receivable_installments WHERE id = :id', [P('id', LInstallment)]));
end;

procedure TFinanceIntegrationTests.ReversalOfAReversalIsRefused;
var
  LEnv: ITestEnv;
  LOrder, LInstallment, LReversal: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LReversal := LEnv.App.Receivables.Reverse(LEnv.App.Receivables.Settle(Settlement(LInstallment, '40,00', LEnv.Key)).SettlementId, 'Erro');
  LRaised := '';
  try
    LEnv.App.Receivables.Reverse(LReversal, 'Estorno do estorno');
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EValidationError', LRaised);
end;

procedure TFinanceIntegrationTests.DatabaseRefusesOverpaymentAndEditingSettlement;
var
  LEnv: ITestEnv;
  LOrder, LInstallment, LSettlementId: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LSettlementId := LEnv.App.Receivables.Settle(Settlement(LInstallment, '40,00', LEnv.Key)).SettlementId;
  LRaised := '';
  try
    LEnv.ExecuteSql('UPDATE receivable_installments SET principal_paid = 100.01 WHERE id = :id', [P('id', LInstallment)]);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EIntegrityViolation', LRaised, 'Pagamento acima do valor');
  LRaised := '';
  try
    LEnv.ExecuteSql('UPDATE receivable_settlements SET principal = 1 WHERE id = :id', [P('id', LSettlementId)]);
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EIntegrityViolation', LRaised, 'Liquidação é imutável');
end;

procedure TFinanceIntegrationTests.OverdueIsDerivedFromTheDate;
var
  LEnv: ITestEnv;
  LOrder, LInstallment: Int64;
  LOnTime, LLate: TDataTable;
  LRow: Integer;
  LFoundOnTime, LFoundLate: Boolean;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LOnTime := LEnv.App.ReadModel.OpenInstallments(Date, False);
  LLate := LEnv.App.ReadModel.OpenInstallments(Date + 31, True);
  LFoundOnTime := False;
  for LRow := 0 to High(LOnTime.Rows) do
    if LOnTime.Cell(LRow, 'ID') = IntToStr(LInstallment) then
    begin
      LFoundOnTime := True;
      Assert.AreEqual('A vencer', LOnTime.Cell(LRow, 'Situação'));
    end;
  LFoundLate := False;
  for LRow := 0 to High(LLate.Rows) do
    if LLate.Cell(LRow, 'ID') = IntToStr(LInstallment) then
    begin
      LFoundLate := True;
      Assert.AreEqual('Vencido', LLate.Cell(LRow, 'Situação'));
    end;
  Assert.IsTrue(LFoundOnTime);
  Assert.IsTrue(LFoundLate, 'Mesmo dado, outro dia: atraso não é status gravado');
end;

procedure TFinanceIntegrationTests.SuggestedChargesFollowConfiguredPolicy;
var
  LEnv: ITestEnv;
  LOrder, LInstallment: Int64;
  LCharges: TLateCharges;
  LDue: TDateTime;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '1000,00', LOrder);
  LDue := Date + 30;
  LCharges := LEnv.App.Receivables.SuggestCharges(LInstallment, LDue);
  Assert.IsTrue(LCharges.Penalty.IsZero, 'No vencimento não há multa');
  LCharges := LEnv.App.Receivables.SuggestCharges(LInstallment, LDue + 15);
  Assert.AreEqual('20.00', LCharges.Penalty.ToInvariant);
  Assert.AreEqual('5.00', LCharges.Interest.ToInvariant);
end;

procedure TFinanceIntegrationTests.CashFlowSeparatesForecastFromRealized;
var
  LEnv: ITestEnv;
  LOrder, LInstallment: Int64;
  LCommand: TSettleCommand;
  LDay: TDateTime;
  LFlow: TDataTable;
begin
  LEnv := NewTestEnv;
  { Data distante: outros testes não gravam nela. }
  LDay := EncodeDate(2099, 1, 15);
  LOrder := ShippedOrder(LEnv, '100,00');
  LEnv.App.Invoicing.InvoiceOrder(LOrder, LDay);
  LInstallment := FirstInstallmentOf(LEnv, LOrder);
  LCommand := Settlement(LInstallment, '30,00', LEnv.Key);
  LCommand.Interest := TMoney.Parse('1,50');
  LCommand.PaidOn := LDay;
  LEnv.App.Receivables.Settle(LCommand);
  LFlow := LEnv.App.ReadModel.CashFlow(LDay, LDay);
  Assert.AreEqual(1, Length(LFlow.Rows));
  Assert.AreEqual('R$ 70,00', LFlow.Cell(0, 'Previsto'), 'Saldo ainda em aberto');
  Assert.AreEqual('R$ 31,50', LFlow.Cell(0, 'Realizado'), 'Principal + juros recebidos');
end;

procedure TFinanceIntegrationTests.TitleWithPaymentCannotBeCancelled;
var
  LEnv: ITestEnv;
  LOrder, LInstallment, LTitle: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LInstallment := InvoicedInstallment(LEnv, '100,00', LOrder);
  LTitle := StrToInt64(LEnv.QueryText('SELECT title_id FROM receivable_installments WHERE id = :id', [P('id', LInstallment)]));
  LEnv.App.Receivables.Settle(Settlement(LInstallment, '1,00', LEnv.Key));
  LRaised := '';
  try
    LEnv.App.Receivables.CancelTitle(LTitle, 'Teste');
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EInvalidTransition', LRaised);
end;

procedure TFinanceIntegrationTests.PaidInvoicesFreeCreditLimit;
var
  LEnv: ITestEnv;
  LProduct, LWarehouse, LCustomer, LOrder: Int64;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LProduct := LEnv.NewProduct('100,00');
  LWarehouse := LEnv.NewWarehouse;
  LCustomer := LEnv.NewCustomer('100,00');
  LEnv.AddStock(LProduct, LWarehouse, '10');
  LOrder := LEnv.App.Sales.ConfirmNew(OrderCommand(LCustomer, [Line(LProduct, LWarehouse, '1')], LEnv.Key)).OrderId;
  LEnv.App.Sales.StartPicking(LOrder);
  LEnv.App.Sales.Ship(LOrder, 0);
  LEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  LRaised := '';
  try
    LEnv.App.Sales.ConfirmNew(OrderCommand(LCustomer, [Line(LProduct, LWarehouse, '1')], LEnv.Key));
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('ECreditLimitExceeded', LRaised, 'Título em aberto consome o limite');
  LEnv.App.Receivables.Settle(Settlement(FirstInstallmentOf(LEnv, LOrder), '100,00', LEnv.Key));
  LEnv.App.Sales.ConfirmNew(OrderCommand(LCustomer, [Line(LProduct, LWarehouse, '1')], LEnv.Key));
  Assert.Pass;
end;

initialization
  TDUnitX.RegisterTestFixture(TFinanceIntegrationTests);

end.
