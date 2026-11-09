unit EF.Domain.Policies;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Money;

type
  TLateCharges = record
    Penalty: TMoney;
    Interest: TMoney;
  end;

  { Multa única + juros simples pró-rata por dia corrido, em pontos-base (200 = 2%). }
  TLateFeePolicy = record
    PenaltyBps: Int64;
    MonthlyInterestBps: Int64;
    function Compute(const AOutstanding: TMoney; const ADueDate, APaidOn: TDateTime): TLateCharges;
  end;

  TCreditPolicy = class
  public
    { Exposição = títulos em aberto + pedidos já reservados e ainda não faturados.
      Limite zero significa cliente sem crédito: vale, e recusa a venda. }
    class procedure Ensure(const ALimit, AExposure, AOrderTotal: TMoney); static;
  end;

implementation

uses
  EF.Domain.Exceptions;

function TLateFeePolicy.Compute(const AOutstanding: TMoney; const ADueDate, APaidOn: TDateTime): TLateCharges;
var
  LDaysLate: Int64;
begin
  Result.Penalty := TMoney.Zero;
  Result.Interest := TMoney.Zero;
  LDaysLate := Trunc(APaidOn) - Trunc(ADueDate);
  if (LDaysLate <= 0) or not AOutstanding.IsPositive then
    Exit;
  Result.Penalty := AOutstanding.PercentBps(PenaltyBps);
  Result.Interest := AOutstanding.Scaled(MonthlyInterestBps * LDaysLate, 10000 * 30);
end;

class procedure TCreditPolicy.Ensure(const ALimit, AExposure, AOrderTotal: TMoney);
begin
  if AExposure + AOrderTotal > ALimit then
    raise ECreditLimitExceeded.CreateFmt('Limite: %s. Em aberto: %s. Este pedido: %s.', [ALimit.ToDisplay, AExposure.ToDisplay, AOrderTotal.ToDisplay]);
end;

end.
