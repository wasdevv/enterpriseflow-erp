unit EF.Application.Finance;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Money, EF.Domain.Policies,
  EF.Application.Ports, EF.Application.Base;

type
  TInvoiceResult = record
    InvoiceId, InvoiceNumber: Int64;
    AlreadyProcessed: Boolean;
  end;

  TInvoicingService = class(TServiceBase)
  public
    { Fluxo crítico: baixa a reserva, cria fatura, título, parcelas e evento na mesma transação. }
    function InvoiceOrder(const AOrderId: Int64; const AFirstDueDate: TDateTime): TInvoiceResult;
  end;

  TSettleCommand = record
    InstallmentId: Int64;
    Principal, Interest, Penalty, Discount: TMoney;
    PaidOn: TDateTime;
    IdempotencyKey, Note: string;
  end;

  TSettleResult = record
    SettlementId: Int64;
    AlreadyProcessed: Boolean;
  end;

  TReceivableService = class(TServiceBase)
  private
    procedure RefreshTitleStatus(const ATitleId: Int64; const ATotal: TMoney);
  public
    function SuggestCharges(const AInstallmentId: Int64; const APaidOn: TDateTime): TLateCharges;
    function Settle(const ACommand: TSettleCommand): TSettleResult;
    { Preserva a liquidação original e grava uma linha compensatória. }
    function Reverse(const ASettlementId: Int64; const AReason: string): Int64;
    procedure CancelTitle(const ATitleId: Int64; const AReason: string);
  end;

implementation

uses
  EF.Domain.Exceptions, EF.Domain.OrderState, EF.Domain.Stock, EF.Domain.Receivables,
  EF.Application.StockLedger,
  EF.Shared.Logging, EF.Shared.Text;

function TInvoicingService.InvoiceOrder(const AOrderId: Int64; const AFirstDueDate: TDateTime): TInvoiceResult;
var
  LStart, LTitleId: Int64;
  LHeader: TOrderHeader;
  LReservations: TReservationArray;
  LLedger: TStockLedger;
  LPlan: TInstallmentPlan;
  LIndex: Integer;
  LEvent: TOutboxEvent;
begin
  BeginOperation(PermInvoiceCreate);
  LStart := NowTick;
  Result.AlreadyProcessed := False;
  FUow.StartTransaction;
  try
    if not FUow.Orders.Lock(AOrderId, LHeader) then
      raise ENotFound.CreateFmt('Pedido %d não encontrado.', [AOrderId]);
    if LHeader.Status = osInvoiced then
    begin
      FUow.Receivables.FindInvoiceOfOrder(AOrderId, Result.InvoiceId, Result.InvoiceNumber);
      Result.AlreadyProcessed := True;
      FUow.Commit;
      Exit;
    end;
    TOrderStateMachine.EnsureTransition(LHeader.Status, osInvoiced);

    LLedger := TStockLedger.Make(FUow.Stock, FCtx);
    LReservations := FUow.Stock.ReservationsOfOrder(AOrderId);
    for LIndex := 0 to High(LReservations) do
    begin
      EnsureReservationActive(LReservations[LIndex].Status);
      if not FUow.Stock.CloseReservation(LReservations[LIndex].Id, rsConsumed) then
        raise EReservationClosed.Create('Reserva encerrada por outra operação.');
      LLedger.Consume(LReservations[LIndex].ProductId, LReservations[LIndex].WarehouseId, LReservations[LIndex].Quantity,
        TStockSource.Make('SALES_ORDER', AOrderId, 'Baixa por faturamento do pedido ' + IntToStr(AOrderId)));
    end;

    LPlan := BuildInstallmentPlan(LHeader.Total, LHeader.Installments, AFirstDueDate, LHeader.IntervalDays);
    Result.InvoiceNumber := FUow.Receivables.NextInvoiceNumber;
    Result.InvoiceId := FUow.Receivables.InsertInvoice(Result.InvoiceNumber, AOrderId, LHeader.CustomerId, LHeader.Total, FCtx.UserId);
    LTitleId := FUow.Receivables.InsertTitle(Result.InvoiceId, LHeader.CustomerId, LHeader.Total);
    for LIndex := 0 to High(LPlan) do
      FUow.Receivables.InsertInstallment(LTitleId, LPlan[LIndex]);

    FUow.Orders.UpdateStatus(AOrderId, osInvoiced, '', 0);
    FUow.Orders.AddHistory(AOrderId, True, LHeader.Status, osInvoiced, FCtx.UserId, 'Fatura ' + IntToStr(Result.InvoiceNumber));
    Audit('invoice.created', 'invoice', Result.InvoiceId, TJsonObjectBuilder.New.Int('number', Result.InvoiceNumber).Int('order_id', AOrderId).Str('total', LHeader.Total.ToInvariant).ToJson);

    { A chamada de rede fica para o worker, depois do commit. Só o evento entra aqui. }
    LEvent.Id := 0;
    LEvent.EventType := 'invoice.issued';
    LEvent.AggregateType := 'invoice';
    LEvent.AggregateId := Result.InvoiceId;
    LEvent.Payload := TJsonObjectBuilder.New.Int('invoice_number', Result.InvoiceNumber).Int('order_id', AOrderId)
      .Int('customer_id', LHeader.CustomerId).Str('total', LHeader.Total.ToInvariant).Int('installments', Length(LPlan)).ToJson;
    LEvent.IdempotencyKey := 'invoice-issued-' + IntToStr(Result.InvoiceId);
    LEvent.CorrelationId := FCtx.CorrelationId;
    LEvent.Attempts := 0;
    FUow.Outbox.Enqueue(LEvent);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
  RecordMetric('order_invoiced', IntToStr(AOrderId), LStart);
  LogEvent(llInfo, 'invoice.created', TJsonObjectBuilder.New.Int('invoice_id', Result.InvoiceId).Int('duration_ms', ElapsedSince(LStart)).ToJson);
end;

procedure TReceivableService.RefreshTitleStatus(const ATitleId: Int64; const ATotal: TMoney);
begin
  FUow.Receivables.UpdateTitleStatus(ATitleId, DeriveTitleStatus(ATotal, FUow.Receivables.TitleSettled(ATitleId)));
end;

function TReceivableService.SuggestCharges(const AInstallmentId: Int64; const APaidOn: TDateTime): TLateCharges;
var
  LInstallment: TInstallmentRecord;
  LPolicy: TLateFeePolicy;
begin
  FUow.StartTransaction;
  try
    if not FUow.Receivables.ReadInstallment(AInstallmentId, LInstallment) then
      raise ENotFound.CreateFmt('Parcela %d não encontrada.', [AInstallmentId]);
    LPolicy.PenaltyBps := StrToInt64Def(FUow.Settings.GetText('late_penalty_bps', '200'), 200);
    LPolicy.MonthlyInterestBps := StrToInt64Def(FUow.Settings.GetText('late_interest_monthly_bps', '100'), 100);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
  Result := LPolicy.Compute(LInstallment.State.Outstanding, LInstallment.DueDate, APaidOn);
end;

function TReceivableService.Settle(const ACommand: TSettleCommand): TSettleResult;
var
  LInstallment: TInstallmentRecord;
  LSettlement: TSettlementRecord;
  LTotal: TMoney;
begin
  BeginOperation(PermReceivableSettle);
  if Trim(ACommand.IdempotencyKey) = '' then
    raise EValidationError.Create('Liquidação exige chave de idempotência.');
  if ACommand.Interest.IsNegative or ACommand.Penalty.IsNegative then
    raise EValidationError.Create('Juros e multa não podem ser negativos.');
  Result.AlreadyProcessed := False;
  Result.SettlementId := 0;
  FUow.StartTransaction;
  try
    if FUow.Receivables.FindSettlementByKey(ACommand.IdempotencyKey, Result.SettlementId) then
    begin
      Result.AlreadyProcessed := True;
      FUow.Commit;
      Exit;
    end;
    if not FUow.Receivables.ReadInstallment(ACommand.InstallmentId, LInstallment) then
      raise ENotFound.CreateFmt('Parcela %d não encontrada.', [ACommand.InstallmentId]);
    FUow.Receivables.LockTitle(LInstallment.TitleId, LTotal);
    FUow.Receivables.LockInstallment(ACommand.InstallmentId, LInstallment);
    if FUow.Receivables.FindSettlementByKey(ACommand.IdempotencyKey, Result.SettlementId) then
    begin
      Result.AlreadyProcessed := True;
      FUow.Commit;
      Exit;
    end;
    LInstallment.State := LInstallment.State.ApplySettlement(ACommand.Principal, ACommand.Discount);
    FUow.Receivables.SaveInstallment(LInstallment);

    LSettlement.Id := 0;
    LSettlement.InstallmentId := ACommand.InstallmentId;
    LSettlement.ReversalOfId := 0;
    LSettlement.UserId := FCtx.UserId;
    LSettlement.Principal := ACommand.Principal;
    LSettlement.Interest := ACommand.Interest;
    LSettlement.Penalty := ACommand.Penalty;
    LSettlement.Discount := ACommand.Discount;
    LSettlement.PaidOn := ACommand.PaidOn;
    LSettlement.IdempotencyKey := ACommand.IdempotencyKey;
    LSettlement.Note := ACommand.Note;
    Result.SettlementId := FUow.Receivables.InsertSettlement(LSettlement);
    RefreshTitleStatus(LInstallment.TitleId, LTotal);
    Audit('receivable.settled', 'installment', ACommand.InstallmentId, TJsonObjectBuilder.New.Int('settlement_id', Result.SettlementId)
      .Str('principal', ACommand.Principal.ToInvariant).Str('interest', ACommand.Interest.ToInvariant)
      .Str('penalty', ACommand.Penalty.ToInvariant).Str('discount', ACommand.Discount.ToInvariant).ToJson);
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      FUow.StartTransaction;
      try
        Result.AlreadyProcessed := FUow.Receivables.FindSettlementByKey(ACommand.IdempotencyKey, Result.SettlementId);
        FUow.Commit;
      except
        FUow.Rollback;
        raise;
      end;
      if not Result.AlreadyProcessed then
        raise;
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

function TReceivableService.Reverse(const ASettlementId: Int64; const AReason: string): Int64;
var
  LOriginal, LReversal: TSettlementRecord;
  LInstallment: TInstallmentRecord;
  LTotal: TMoney;
begin
  BeginOperation(PermReceivableReverse);
  if Trim(AReason) = '' then
    raise EValidationError.Create('Estorno exige motivo.');
  FUow.StartTransaction;
  try
    if not FUow.Receivables.ReadSettlement(ASettlementId, LOriginal) then
      raise ENotFound.CreateFmt('Liquidação %d não encontrada.', [ASettlementId]);
    if LOriginal.ReversalOfId <> 0 then
      raise EValidationError.Create('Um estorno não pode ser estornado.');
    if not FUow.Receivables.ReadInstallment(LOriginal.InstallmentId, LInstallment) then
      raise ENotFound.CreateFmt('Parcela %d não encontrada.', [LOriginal.InstallmentId]);
    FUow.Receivables.LockTitle(LInstallment.TitleId, LTotal);
    FUow.Receivables.LockInstallment(LOriginal.InstallmentId, LInstallment);
    if FUow.Receivables.HasReversal(ASettlementId) then
      raise EAlreadyReversed.Create('Esta liquidação já foi estornada.');

    LInstallment.State := LInstallment.State.RevertSettlement(LOriginal.Principal, LOriginal.Discount);
    FUow.Receivables.SaveInstallment(LInstallment);
    LReversal := LOriginal;
    LReversal.Id := 0;
    LReversal.ReversalOfId := ASettlementId;
    LReversal.UserId := FCtx.UserId;
    LReversal.Principal := LOriginal.Principal.Negated;
    LReversal.Interest := LOriginal.Interest.Negated;
    LReversal.Penalty := LOriginal.Penalty.Negated;
    LReversal.Discount := LOriginal.Discount.Negated;
    LReversal.PaidOn := FClock.Today;
    LReversal.IdempotencyKey := 'reversal-' + IntToStr(ASettlementId);
    LReversal.Note := AReason;
    Result := FUow.Receivables.InsertSettlement(LReversal);
    RefreshTitleStatus(LInstallment.TitleId, LTotal);
    Audit('receivable.reversed', 'installment', LOriginal.InstallmentId, TJsonObjectBuilder.New.Int('settlement_id', ASettlementId).Int('reversal_id', Result).Str('reason', AReason).ToJson);
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      raise EAlreadyReversed.Create('Esta liquidação já foi estornada.');
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

procedure TReceivableService.CancelTitle(const ATitleId: Int64; const AReason: string);
var
  LTotal: TMoney;
begin
  BeginOperation(PermReceivableReverse);
  if Trim(AReason) = '' then
    raise EValidationError.Create('Cancelamento de título exige motivo.');
  FUow.StartTransaction;
  try
    if not FUow.Receivables.LockTitle(ATitleId, LTotal) then
      raise ENotFound.CreateFmt('Título %d não encontrado.', [ATitleId]);
    if not FUow.Receivables.TitleSettled(ATitleId).IsZero then
      raise EInvalidTransition.Create('Título com liquidação não pode ser cancelado. Estorne antes.');
    FUow.Receivables.UpdateTitleStatus(ATitleId, tsCancelled);
    Audit('receivable.title_cancelled', 'receivable_title', ATitleId, TJsonObjectBuilder.New.Str('reason', AReason).ToJson);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

end.
