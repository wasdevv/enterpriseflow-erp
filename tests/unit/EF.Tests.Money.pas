unit EF.Tests.Money;

{$I EF.inc}
{$M+}

interface

uses
  DUnitX.TestFramework;

type
  TMoneyTests = class(TObject)
  published
    procedure AddingCentsHasNoFloatingPointError;
    procedure ParseAcceptsBrazilianAndInvariantFormats;
    procedure ParseRejectsThreeDecimalsAndGarbage;
    procedure DisplayGroupsThousands;
    procedure CurrencyRoundTripIsExactAtLargeValues;
    procedure SplitNeverLosesACent;
    procedure TimesRoundsHalfCentUp;
    procedure PercentRoundsHalfCentUp;
  end;

  TQuantityTests = class(TObject)
  published
    procedure ParseAcceptsFractionForMeterSoldCable;
    procedure ParseRejectsFourDecimalsAndGarbage;
    procedure TextDropsTrailingZeros;
    procedure CurrencyRoundTripIsExact;
  end;

implementation

uses
  SysUtils,
  EF.Domain.Money, EF.Domain.Quantity, EF.Domain.Exceptions;

procedure TMoneyTests.AddingCentsHasNoFloatingPointError;
var
  LTotal: TMoney;
  LIndex: Integer;
begin
  { Com Double, somar 0,10 dez vezes não dá exatamente 1,00. }
  LTotal := TMoney.Zero;
  for LIndex := 1 to 10 do
    LTotal := LTotal + TMoney.Parse('0,10');
  Assert.IsTrue(LTotal = TMoney.Parse('1,00'));
  Assert.AreEqual('1.00', LTotal.ToInvariant);
end;

procedure TMoneyTests.ParseAcceptsBrazilianAndInvariantFormats;
begin
  Assert.AreEqual('1234.56', TMoney.Parse('1234,56').ToInvariant);
  Assert.AreEqual('1234.56', TMoney.Parse('1.234,56').ToInvariant);
  Assert.AreEqual('1234.56', TMoney.Parse('1234.56').ToInvariant);
  Assert.AreEqual('1234.00', TMoney.Parse('1.234').ToInvariant);
  Assert.AreEqual('1234567.89', TMoney.Parse('R$ 1.234.567,89').ToInvariant);
  Assert.AreEqual('10.50', TMoney.Parse('10,5').ToInvariant);
  Assert.AreEqual('-3.20', TMoney.Parse('-3,20').ToInvariant);
end;

procedure TMoneyTests.ParseRejectsThreeDecimalsAndGarbage;
const
  CBad: array [0 .. 4] of string = ('1,234', '', 'abc', '12,3x', '1a2');
var
  LIndex: Integer;
  LRaised: Boolean;
begin
  for LIndex := Low(CBad) to High(CBad) do
  begin
    LRaised := False;
    try
      TMoney.Parse(CBad[LIndex]);
    except
      on EValidationError do
        LRaised := True;
    end;
    Assert.IsTrue(LRaised, 'Deveria recusar: ' + CBad[LIndex]);
  end;
end;

procedure TMoneyTests.DisplayGroupsThousands;
begin
  Assert.AreEqual('R$ 1.234.567,89', TMoney.FromCents(123456789).ToDisplay);
  Assert.AreEqual('R$ 0,05', TMoney.FromCents(5).ToDisplay);
  Assert.AreEqual('R$ 999,00', TMoney.FromCents(99900).ToDisplay);
  Assert.AreEqual('-R$ 1.000,00', TMoney.FromCents(-100000).ToDisplay);
end;

procedure TMoneyTests.CurrencyRoundTripIsExactAtLargeValues;
var
  LOriginal: TMoney;
begin
  { 15 dígitos significativos: o limite onde um cast para Double começa a perder precisão. }
  LOriginal := TMoney.FromCents(999999999999999);
  Assert.AreEqual(LOriginal.ToInvariant, TMoney.FromCurrency(LOriginal.ToCurrency).ToInvariant);
  LOriginal := TMoney.FromCents(-1);
  Assert.AreEqual('-0.01', TMoney.FromCurrency(LOriginal.ToCurrency).ToInvariant);
end;

procedure TMoneyTests.SplitNeverLosesACent;
var
  LParts: TMoneyArray;
  LSum: Int64;
  LIndex: Integer;
begin
  LParts := TMoney.FromCents(10000).Split(3);
  Assert.AreEqual(3, Length(LParts));
  Assert.AreEqual('3334', IntToStr(LParts[0]));
  Assert.AreEqual('3333', IntToStr(LParts[1]));
  Assert.AreEqual('3333', IntToStr(LParts[2]));
  LSum := 0;
  for LIndex := 0 to High(LParts) do
    LSum := LSum + LParts[LIndex];
  Assert.AreEqual('10000', IntToStr(LSum));
end;

procedure TMoneyTests.TimesRoundsHalfCentUp;
begin
  { R$ 3,33 x 1,5 m = 4,995 -> 5,00 }
  Assert.AreEqual('5.00', TMoney.Parse('3,33').Times(TQuantity.Parse('1,5')).ToInvariant);
  { R$ 0,99 x 2,125 m = 2,10375 -> 2,10 }
  Assert.AreEqual('2.10', TMoney.Parse('0,99').Times(TQuantity.Parse('2,125')).ToInvariant);
end;

procedure TMoneyTests.PercentRoundsHalfCentUp;
begin
  Assert.AreEqual('2.00', TMoney.Parse('100,00').PercentBps(200).ToInvariant);
  { 2% de 1,25 = 0,025 -> 0,03 }
  Assert.AreEqual('0.03', TMoney.Parse('1,25').PercentBps(200).ToInvariant);
end;

procedure TQuantityTests.ParseAcceptsFractionForMeterSoldCable;
begin
  Assert.AreEqual('1500', IntToStr(TQuantity.Parse('1,5').Thousandths));
  Assert.AreEqual('1500', IntToStr(TQuantity.Parse('1.500').Thousandths));
  Assert.AreEqual('7000', IntToStr(TQuantity.Parse('7').Thousandths));
  Assert.AreEqual('-250', IntToStr(TQuantity.Parse('-0,25').Thousandths));
end;

procedure TQuantityTests.ParseRejectsFourDecimalsAndGarbage;
const
  CBad: array [0 .. 4] of string = ('1,2345', '', 'x', '1,2,3', ',5');
var
  LIndex: Integer;
  LRaised: Boolean;
begin
  for LIndex := Low(CBad) to High(CBad) do
  begin
    LRaised := False;
    try
      TQuantity.Parse(CBad[LIndex]);
    except
      on EValidationError do
        LRaised := True;
    end;
    Assert.IsTrue(LRaised, 'Deveria recusar: ' + CBad[LIndex]);
  end;
end;

procedure TQuantityTests.TextDropsTrailingZeros;
begin
  Assert.AreEqual('1,5', TQuantity.Parse('1,500').ToText);
  Assert.AreEqual('2', TQuantity.FromUnits(2).ToText);
  Assert.AreEqual('0,005', TQuantity.FromThousandths(5).ToText);
  Assert.AreEqual('-3,25', TQuantity.Parse('-3,25').ToText);
end;

procedure TQuantityTests.CurrencyRoundTripIsExact;
var
  LOriginal: TQuantity;
begin
  LOriginal := TQuantity.FromThousandths(123456789012);
  Assert.AreEqual('123456789012', IntToStr(TQuantity.FromCurrency(LOriginal.ToCurrency).Thousandths));
end;

initialization
  TDUnitX.RegisterTestFixture(TMoneyTests);
  TDUnitX.RegisterTestFixture(TQuantityTests);

end.
