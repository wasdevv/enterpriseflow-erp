unit EF.Domain.Quantity;

{$I EF.inc}

interface

uses
  SysUtils;

type
  { Quantidade em milésimos, igual a NUMERIC(15,3). Cabo vendido por metro aceita fração. }
  TQuantity = record
  private
    FThousandths: Int64;
  public
    class function FromThousandths(const AValue: Int64): TQuantity; static;
    class function FromUnits(const AValue: Int64): TQuantity; static;
    class function Zero: TQuantity; static;
    { Aceita vírgula ou ponto como separador decimal, sem agrupamento de milhar. }
    class function Parse(const AText: string): TQuantity; static;
    class function FromCurrency(const AValue: Currency): TQuantity; static;
    function ToCurrency: Currency;
    function Thousandths: Int64;
    function IsZero: Boolean;
    function IsPositive: Boolean;
    function IsNegative: Boolean;
    function Negated: TQuantity;
    function ToText: string;
    class operator Add(const A, B: TQuantity): TQuantity;
    class operator Subtract(const A, B: TQuantity): TQuantity;
    class operator Equal(const A, B: TQuantity): Boolean;
    class operator NotEqual(const A, B: TQuantity): Boolean;
    class operator LessThan(const A, B: TQuantity): Boolean;
    class operator LessThanOrEqual(const A, B: TQuantity): Boolean;
    class operator GreaterThan(const A, B: TQuantity): Boolean;
    class operator GreaterThanOrEqual(const A, B: TQuantity): Boolean;
  end;

implementation

uses
  EF.Domain.Exceptions;

class function TQuantity.FromThousandths(const AValue: Int64): TQuantity;
begin
  Result.FThousandths := AValue;
end;

class function TQuantity.FromUnits(const AValue: Int64): TQuantity;
begin
  Result.FThousandths := AValue * 1000;
end;

class function TQuantity.Zero: TQuantity;
begin
  Result.FThousandths := 0;
end;

class function TQuantity.Parse(const AText: string): TQuantity;
var
  LText, LWhole, LFraction: string;
  LSeparator, LIndex: Integer;
  LNegative: Boolean;
  LWholeValue, LFractionValue: Int64;
begin
  LText := Trim(AText);
  LNegative := (LText <> '') and (LText[1] = '-');
  if LNegative then
    Delete(LText, 1, 1);
  if LText = '' then
    raise EValidationError.Create('Quantidade inválida: informe um valor.');

  LSeparator := 0;
  for LIndex := 1 to Length(LText) do
    if CharInSet(LText[LIndex], [',', '.']) then
    begin
      if LSeparator <> 0 then
        raise EValidationError.CreateFmt('Quantidade inválida: "%s".', [AText]);
      LSeparator := LIndex;
    end
    else if not CharInSet(LText[LIndex], ['0'..'9']) then
      raise EValidationError.CreateFmt('Quantidade inválida: "%s".', [AText]);

  if LSeparator = 0 then
  begin
    LWhole := LText;
    LFraction := '';
  end
  else
  begin
    LWhole := Copy(LText, 1, LSeparator - 1);
    LFraction := Copy(LText, LSeparator + 1, MaxInt);
  end;
  if (LWhole = '') or (Length(LFraction) > 3) or (Length(LWhole) > 12) then
    raise EValidationError.CreateFmt('Quantidade inválida: "%s".', [AText]);

  while Length(LFraction) < 3 do
    LFraction := LFraction + '0';
  LWholeValue := StrToInt64(LWhole);
  LFractionValue := StrToInt64(LFraction);
  Result.FThousandths := LWholeValue * 1000 + LFractionValue;
  if LNegative then
    Result.FThousandths := -Result.FThousandths;
end;

class function TQuantity.FromCurrency(const AValue: Currency): TQuantity;
begin
  { Currency é um Int64 escalado por 10.000: dividir o inteiro evita ponto flutuante,
    que em Win64 teria só a precisão de Double. }
  Result.FThousandths := PInt64(@AValue)^ div 10;
end;

function TQuantity.ToCurrency: Currency;
begin
  PInt64(@Result)^ := FThousandths * 10;
end;

function TQuantity.Thousandths: Int64;
begin
  Result := FThousandths;
end;

function TQuantity.IsZero: Boolean;
begin
  Result := FThousandths = 0;
end;

function TQuantity.IsPositive: Boolean;
begin
  Result := FThousandths > 0;
end;

function TQuantity.IsNegative: Boolean;
begin
  Result := FThousandths < 0;
end;

function TQuantity.Negated: TQuantity;
begin
  Result.FThousandths := -FThousandths;
end;

function TQuantity.ToText: string;
var
  LAbs: Int64;
  LFraction: string;
begin
  LAbs := Abs(FThousandths);
  Result := IntToStr(LAbs div 1000);
  if LAbs mod 1000 <> 0 then
  begin
    LFraction := Format('%.3d', [LAbs mod 1000]);
    while LFraction[Length(LFraction)] = '0' do
      Delete(LFraction, Length(LFraction), 1);
    Result := Result + ',' + LFraction;
  end;
  if FThousandths < 0 then
    Result := '-' + Result;
end;

class operator TQuantity.Add(const A, B: TQuantity): TQuantity;
begin
  Result.FThousandths := A.FThousandths + B.FThousandths;
end;

class operator TQuantity.Subtract(const A, B: TQuantity): TQuantity;
begin
  Result.FThousandths := A.FThousandths - B.FThousandths;
end;

class operator TQuantity.Equal(const A, B: TQuantity): Boolean;
begin
  Result := A.FThousandths = B.FThousandths;
end;

class operator TQuantity.NotEqual(const A, B: TQuantity): Boolean;
begin
  Result := A.FThousandths <> B.FThousandths;
end;

class operator TQuantity.LessThan(const A, B: TQuantity): Boolean;
begin
  Result := A.FThousandths < B.FThousandths;
end;

class operator TQuantity.LessThanOrEqual(const A, B: TQuantity): Boolean;
begin
  Result := A.FThousandths <= B.FThousandths;
end;

class operator TQuantity.GreaterThan(const A, B: TQuantity): Boolean;
begin
  Result := A.FThousandths > B.FThousandths;
end;

class operator TQuantity.GreaterThanOrEqual(const A, B: TQuantity): Boolean;
begin
  Result := A.FThousandths >= B.FThousandths;
end;

end.
