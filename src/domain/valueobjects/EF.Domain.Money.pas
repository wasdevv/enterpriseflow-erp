unit EF.Domain.Money;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Quantity;

type
  TMoneyArray = array of Int64;

  { Dinheiro em centavos, igual a NUMERIC(18,2). Nunca Single nem Double. }
  TMoney = record
  private
    FCents: Int64;
  public
    class function FromCents(const AValue: Int64): TMoney; static;
    class function Zero: TMoney; static;
    { Aceita 1234,56 / 1.234,56 / 1234.56 / R$ 10. Recusa mais de 2 casas decimais. }
    class function Parse(const AText: string): TMoney; static;
    class function FromCurrency(const AValue: Currency): TMoney; static;
    function ToCurrency: Currency;
    function Cents: Int64;
    function IsZero: Boolean;
    function IsPositive: Boolean;
    function IsNegative: Boolean;
    function Negated: TMoney;
    { Multiplica por quantidade, arredondando meio centavo para cima. }
    function Times(const AQuantity: TQuantity): TMoney;
    { Percentual em pontos-base: 200 = 2%. }
    function PercentBps(const ABasisPoints: Int64): TMoney;
    { Multiplica antes de dividir, para não perder centavos. Arredonda meio para cima. }
    function Scaled(const ANumerator, ADenominator: Int64): TMoney;
    { Divide sem perder centavo: o resto vai para as primeiras partes. }
    function Split(const AParts: Integer): TMoneyArray;
    function ToInvariant: string;
    function ToDisplay: string;
    class operator Add(const A, B: TMoney): TMoney;
    class operator Subtract(const A, B: TMoney): TMoney;
    class operator Equal(const A, B: TMoney): Boolean;
    class operator NotEqual(const A, B: TMoney): Boolean;
    class operator LessThan(const A, B: TMoney): Boolean;
    class operator LessThanOrEqual(const A, B: TMoney): Boolean;
    class operator GreaterThan(const A, B: TMoney): Boolean;
    class operator GreaterThanOrEqual(const A, B: TMoney): Boolean;
  end;

implementation

uses
  EF.Domain.Exceptions;

class function TMoney.FromCents(const AValue: Int64): TMoney;
begin
  Result.FCents := AValue;
end;

class function TMoney.Zero: TMoney;
begin
  Result.FCents := 0;
end;

class function TMoney.Parse(const AText: string): TMoney;
var
  LText, LDigits, LWhole, LFraction: string;
  LIndex, LDecimalAt: Integer;
  LNegative: Boolean;
begin
  LText := Trim(StringReplace(AText, 'R$', '', [rfIgnoreCase]));
  LNegative := (LText <> '') and (LText[1] = '-');
  if LNegative then
    LText := Trim(Copy(LText, 2, MaxInt));
  if LText = '' then
    raise EValidationError.Create('Valor inválido: informe um valor.');

  { O último separador só é decimal se vier seguido de no máximo 2 dígitos. Com 3
    dígitos, "1.234" é milhar; "1,234" é tentativa de 3 casas e é recusada. }
  LDecimalAt := 0;
  for LIndex := Length(LText) downto 1 do
    if CharInSet(LText[LIndex], [',', '.']) then
    begin
      if Length(LText) - LIndex <= 2 then
        LDecimalAt := LIndex
      else if (LText[LIndex] = ',') then
        raise EValidationError.CreateFmt('Valor inválido: "%s".', [AText]);
      Break;
    end;

  if LDecimalAt = 0 then
  begin
    LWhole := LText;
    LFraction := '';
  end
  else
  begin
    LWhole := Copy(LText, 1, LDecimalAt - 1);
    LFraction := Copy(LText, LDecimalAt + 1, MaxInt);
  end;

  LDigits := '';
  for LIndex := 1 to Length(LWhole) do
    if CharInSet(LWhole[LIndex], ['0'..'9']) then
      LDigits := LDigits + LWhole[LIndex]
    else if not CharInSet(LWhole[LIndex], ['.', ',']) then
      raise EValidationError.CreateFmt('Valor inválido: "%s".', [AText]);
  for LIndex := 1 to Length(LFraction) do
    if not CharInSet(LFraction[LIndex], ['0'..'9']) then
      raise EValidationError.CreateFmt('Valor inválido: "%s".', [AText]);
  if (LDigits = '') or (Length(LDigits) > 16) then
    raise EValidationError.CreateFmt('Valor inválido: "%s".', [AText]);

  while Length(LFraction) < 2 do
    LFraction := LFraction + '0';
  Result.FCents := StrToInt64(LDigits) * 100 + StrToInt64(LFraction);
  if LNegative then
    Result.FCents := -Result.FCents;
end;

class function TMoney.FromCurrency(const AValue: Currency): TMoney;
var
  LRaw: Int64;
begin
  { Currency é um Int64 escalado por 10.000: dividir o inteiro evita ponto flutuante. }
  LRaw := PInt64(@AValue)^;
  if LRaw >= 0 then
    Result.FCents := (LRaw + 50) div 100
  else
    Result.FCents := -((-LRaw + 50) div 100);
end;

function TMoney.ToCurrency: Currency;
begin
  PInt64(@Result)^ := FCents * 100;
end;

function TMoney.Cents: Int64;
begin
  Result := FCents;
end;

function TMoney.IsZero: Boolean;
begin
  Result := FCents = 0;
end;

function TMoney.IsPositive: Boolean;
begin
  Result := FCents > 0;
end;

function TMoney.IsNegative: Boolean;
begin
  Result := FCents < 0;
end;

function TMoney.Negated: TMoney;
begin
  Result.FCents := -FCents;
end;

function RoundDiv(const ANumerator, ADenominator: Int64): Int64;
begin
  if ANumerator >= 0 then
    Result := (ANumerator + ADenominator div 2) div ADenominator
  else
    Result := -((-ANumerator + ADenominator div 2) div ADenominator);
end;

function TMoney.Times(const AQuantity: TQuantity): TMoney;
begin
  Result.FCents := RoundDiv(FCents * AQuantity.Thousandths, 1000);
end;

function TMoney.PercentBps(const ABasisPoints: Int64): TMoney;
begin
  Result.FCents := RoundDiv(FCents * ABasisPoints, 10000);
end;

function TMoney.Scaled(const ANumerator, ADenominator: Int64): TMoney;
begin
  Result.FCents := RoundDiv(FCents * ANumerator, ADenominator);
end;

function TMoney.Split(const AParts: Integer): TMoneyArray;
var
  LIndex: Integer;
  LBase, LRemainder: Int64;
begin
  if AParts <= 0 then
    raise EValidationError.Create('Número de parcelas deve ser positivo.');
  SetLength(Result, AParts);
  LBase := FCents div AParts;
  LRemainder := FCents mod AParts;
  for LIndex := 0 to AParts - 1 do
  begin
    Result[LIndex] := LBase;
    if LIndex < LRemainder then
      Inc(Result[LIndex]);
  end;
end;

function TMoney.ToInvariant: string;
var
  LAbs: Int64;
begin
  LAbs := Abs(FCents);
  Result := Format('%d.%.2d', [LAbs div 100, LAbs mod 100]);
  if FCents < 0 then
    Result := '-' + Result;
end;

function TMoney.ToDisplay: string;
var
  LAbs: Int64;
  LWhole: string;
  LIndex: Integer;
begin
  LAbs := Abs(FCents);
  LWhole := IntToStr(LAbs div 100);
  LIndex := Length(LWhole) - 3;
  while LIndex > 0 do
  begin
    Insert('.', LWhole, LIndex + 1);
    Dec(LIndex, 3);
  end;
  Result := Format('R$ %s,%.2d', [LWhole, LAbs mod 100]);
  if FCents < 0 then
    Result := '-' + Result;
end;

class operator TMoney.Add(const A, B: TMoney): TMoney;
begin
  Result.FCents := A.FCents + B.FCents;
end;

class operator TMoney.Subtract(const A, B: TMoney): TMoney;
begin
  Result.FCents := A.FCents - B.FCents;
end;

class operator TMoney.Equal(const A, B: TMoney): Boolean;
begin
  Result := A.FCents = B.FCents;
end;

class operator TMoney.NotEqual(const A, B: TMoney): Boolean;
begin
  Result := A.FCents <> B.FCents;
end;

class operator TMoney.LessThan(const A, B: TMoney): Boolean;
begin
  Result := A.FCents < B.FCents;
end;

class operator TMoney.LessThanOrEqual(const A, B: TMoney): Boolean;
begin
  Result := A.FCents <= B.FCents;
end;

class operator TMoney.GreaterThan(const A, B: TMoney): Boolean;
begin
  Result := A.FCents > B.FCents;
end;

class operator TMoney.GreaterThanOrEqual(const A, B: TMoney): Boolean;
begin
  Result := A.FCents >= B.FCents;
end;

end.
