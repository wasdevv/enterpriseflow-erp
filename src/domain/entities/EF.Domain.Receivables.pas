unit EF.Domain.Receivables;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Money;

type
  TTitleStatus = (tsOpen, tsPartiallyPaid, tsPaid, tsCancelled);

  { Parcela. Principal e desconto abatem o saldo; juros e multa são cobrados por fora. }
  TInstallmentState = record
    Amount: TMoney;
    PrincipalPaid: TMoney;
    DiscountGranted: TMoney;
    function Outstanding: TMoney;
    function ApplySettlement(const APrincipal, ADiscount: TMoney): TInstallmentState;
    function RevertSettlement(const APrincipal, ADiscount: TMoney): TInstallmentState;
    function IsOverdue(const ADueDate, AToday: TDateTime): Boolean;
  end;

  TPlannedInstallment = record
    Number: Integer;
    DueDate: TDateTime;
    Amount: TMoney;
  end;

  TInstallmentPlan = array of TPlannedInstallment;

function BuildInstallmentPlan(const ATotal: TMoney; const ACount: Integer; const AFirstDue: TDateTime; const AIntervalDays: Integer): TInstallmentPlan;
function DeriveTitleStatus(const ATotal, ASettled: TMoney): TTitleStatus;
function TitleStatusCode(const AStatus: TTitleStatus): string;

implementation

uses
  EF.Domain.Exceptions;

const
  CTitleCodes: array [TTitleStatus] of string = ('OPEN', 'PARTIALLY_PAID', 'PAID', 'CANCELLED');

function TInstallmentState.Outstanding: TMoney;
begin
  Result := Amount - PrincipalPaid - DiscountGranted;
end;

function TInstallmentState.ApplySettlement(const APrincipal, ADiscount: TMoney): TInstallmentState;
begin
  if APrincipal.IsNegative or ADiscount.IsNegative then
    raise EValidationError.Create('Valores de liquidação não podem ser negativos.');
  if (APrincipal + ADiscount).IsZero then
    raise EValidationError.Create('Informe o valor pago ou o desconto.');
  if APrincipal + ADiscount > Outstanding then
    raise EOverpayment.CreateFmt('Saldo em aberto: %s. Informado: %s.', [Outstanding.ToDisplay, (APrincipal + ADiscount).ToDisplay]);
  Result := Self;
  Result.PrincipalPaid := PrincipalPaid + APrincipal;
  Result.DiscountGranted := DiscountGranted + ADiscount;
end;

function TInstallmentState.RevertSettlement(const APrincipal, ADiscount: TMoney): TInstallmentState;
begin
  if (APrincipal > PrincipalPaid) or (ADiscount > DiscountGranted) then
    raise EValidationError.Create('Estorno maior que o valor já liquidado na parcela.');
  Result := Self;
  Result.PrincipalPaid := PrincipalPaid - APrincipal;
  Result.DiscountGranted := DiscountGranted - ADiscount;
end;

function TInstallmentState.IsOverdue(const ADueDate, AToday: TDateTime): Boolean;
begin
  Result := Outstanding.IsPositive and (Trunc(AToday) > Trunc(ADueDate));
end;

function BuildInstallmentPlan(const ATotal: TMoney; const ACount: Integer; const AFirstDue: TDateTime; const AIntervalDays: Integer): TInstallmentPlan;
var
  LParts: TMoneyArray;
  LIndex: Integer;
begin
  if not ATotal.IsPositive then
    raise EValidationError.Create('O total a parcelar deve ser maior que zero.');
  if (ACount < 1) or (ACount > 48) then
    raise EValidationError.Create('O número de parcelas deve ficar entre 1 e 48.');
  if (AIntervalDays < 1) or (AIntervalDays > 180) then
    raise EValidationError.Create('O intervalo entre parcelas deve ficar entre 1 e 180 dias.');
  if ATotal.Cents < ACount then
    raise EValidationError.Create('Parcela não pode ficar abaixo de R$ 0,01.');

  LParts := ATotal.Split(ACount);
  SetLength(Result, ACount);
  for LIndex := 0 to ACount - 1 do
  begin
    Result[LIndex].Number := LIndex + 1;
    Result[LIndex].DueDate := Trunc(AFirstDue) + LIndex * AIntervalDays;
    Result[LIndex].Amount := TMoney.FromCents(LParts[LIndex]);
  end;
end;

function DeriveTitleStatus(const ATotal, ASettled: TMoney): TTitleStatus;
begin
  if ASettled.IsZero then
    Result := tsOpen
  else if ASettled >= ATotal then
    Result := tsPaid
  else
    Result := tsPartiallyPaid;
end;

function TitleStatusCode(const AStatus: TTitleStatus): string;
begin
  Result := CTitleCodes[AStatus];
end;

end.
