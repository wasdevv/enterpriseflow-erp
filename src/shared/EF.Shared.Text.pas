unit EF.Shared.Text;

{$I EF.inc}

interface

uses
  SysUtils;

type
  { Monta JSON sem depender de System.JSON (Delphi) nem fpjson (FPC). Só escreve: o app
    nunca precisa interpretar a resposta do serviço externo, só o status. }
  TJsonObjectBuilder = record
  private
    FBody: string;
    procedure AddRaw(const AName, ARawValue: string);
  public
    class function New: TJsonObjectBuilder; static;
    function Str(const AName, AValue: string): TJsonObjectBuilder;
    function Int(const AName: string; const AValue: Int64): TJsonObjectBuilder;
    function Raw(const AName, ARawJson: string): TJsonObjectBuilder;
    function ToJson: string;
  end;

function JsonEscape(const AValue: string): string;
{ Mascara o valor de campos sensíveis em JSON ou chave=valor antes de ir para o log. }
function RedactSecrets(const AText: string): string;
function NewCorrelationId: string;
function IsoTimestamp(const AValue: TDateTime): string;
function IsoDate(const AValue: TDateTime): string;

implementation

function JsonEscape(const AValue: string): string;
var
  LIndex: Integer;
begin
  Result := '';
  for LIndex := 1 to Length(AValue) do
    case AValue[LIndex] of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(AValue[LIndex]) < 32 then
        Result := Result + '\u' + LowerCase(IntToHex(Ord(AValue[LIndex]), 4))
      else
        Result := Result + AValue[LIndex];
    end;
end;

class function TJsonObjectBuilder.New: TJsonObjectBuilder;
begin
  Result.FBody := '';
end;

procedure TJsonObjectBuilder.AddRaw(const AName, ARawValue: string);
begin
  if FBody <> '' then
    FBody := FBody + ',';
  FBody := FBody + '"' + JsonEscape(AName) + '":' + ARawValue;
end;

function TJsonObjectBuilder.Str(const AName, AValue: string): TJsonObjectBuilder;
begin
  AddRaw(AName, '"' + JsonEscape(AValue) + '"');
  Result := Self;
end;

function TJsonObjectBuilder.Int(const AName: string; const AValue: Int64): TJsonObjectBuilder;
begin
  AddRaw(AName, IntToStr(AValue));
  Result := Self;
end;

function TJsonObjectBuilder.Raw(const AName, ARawJson: string): TJsonObjectBuilder;
begin
  AddRaw(AName, ARawJson);
  Result := Self;
end;

function TJsonObjectBuilder.ToJson: string;
begin
  Result := '{' + FBody + '}';
end;

function RedactSecrets(const AText: string): string;
const
  CKeys: array [0 .. 8] of string = ('password', 'senha', 'token', 'authorization', 'api_key', 'apikey', 'secret', 'card', 'cartao');
var
  LLower: string;
  LKey, LStart, LCursor, LEnd: Integer;
  LQuote: Char;
begin
  Result := AText;
  for LKey := Low(CKeys) to High(CKeys) do
  begin
    LCursor := 1;
    repeat
      LLower := LowerCase(Result);
      LStart := LCursor;
      while (LStart <= Length(LLower) - Length(CKeys[LKey]) + 1) and (Copy(LLower, LStart, Length(CKeys[LKey])) <> CKeys[LKey]) do
        Inc(LStart);
      if LStart > Length(LLower) - Length(CKeys[LKey]) + 1 then
        Break;
      LCursor := LStart + Length(CKeys[LKey]);
      { Pula o restante do nome do campo (ex.: card_number) e o separador. }
      while (LCursor <= Length(Result)) and CharInSet(Result[LCursor], ['a'..'z', 'A'..'Z', '0'..'9', '_', '-']) do
        Inc(LCursor);
      if (LCursor <= Length(Result)) and (Result[LCursor] = '"') then
        Inc(LCursor);
      while (LCursor <= Length(Result)) and (Result[LCursor] = ' ') do
        Inc(LCursor);
      if (LCursor > Length(Result)) or not CharInSet(Result[LCursor], [':', '=']) then
        Continue;
      Inc(LCursor);
      while (LCursor <= Length(Result)) and (Result[LCursor] = ' ') do
        Inc(LCursor);
      LEnd := LCursor;
      if (LCursor <= Length(Result)) and CharInSet(Result[LCursor], ['"', '''']) then
      begin
        LQuote := Result[LCursor];
        Inc(LCursor);
        LEnd := LCursor;
        while (LEnd <= Length(Result)) and (Result[LEnd] <> LQuote) do
        begin
          if (Result[LEnd] = '\') and (LEnd < Length(Result)) then
            Inc(LEnd);
          Inc(LEnd);
        end;
      end
      else
        while (LEnd <= Length(Result)) and not CharInSet(Result[LEnd], [',', ';', '&', ' ', '}', #13, #10]) do
          Inc(LEnd);
      Result := Copy(Result, 1, LCursor - 1) + '***' + Copy(Result, LEnd, MaxInt);
      LCursor := LCursor + 3;
    until False;
  end;
end;

function NewCorrelationId: string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := LowerCase(Copy(GUIDToString(LGuid), 2, 36));
end;

function IsoTimestamp(const AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz', AValue);
end;

function IsoDate(const AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd', AValue);
end;

end.
