unit EF.Infrastructure.Database;

{$I EF.inc}

interface

uses
  SysUtils, Classes, DB,
  EF.Domain.Money, EF.Domain.Quantity;

type
  TDbParamKind = (dpkNull, dpkInt, dpkText, dpkCurrency, dpkDateTime, dpkDate, dpkBool);

  TDbParam = record
    Name: string;
    Kind: TDbParamKind;
    IntValue: Int64;
    TextValue: string;
    CurrencyValue: Currency;
    DateValue: TDateTime;
    BoolValue: Boolean;
  end;

  IDbReader = interface
    function Eof: Boolean;
    procedure Next;
    function Int(const AField: string): Int64;
    function Str(const AField: string): string;
    function Money(const AField: string): TMoney;
    function Qty(const AField: string): TQuantity;
    function Date(const AField: string): TDateTime;
    function Bool(const AField: string): Boolean;
    function IsNull(const AField: string): Boolean;
    function FieldCount: Integer;
    function FieldName(const AIndex: Integer): string;
    { Texto para grade: dinheiro em R$, quantidade sem zeros à direita, data dd/mm/aaaa. }
    function DisplayText(const AIndex: Integer): string;
  end;

  IDbSession = interface
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    function Query(const ASql: string): IDbReader; overload;
    function Query(const ASql: string; const AParams: array of TDbParam): IDbReader; overload;
    function Execute(const ASql: string): Integer; overload;
    function Execute(const ASql: string; const AParams: array of TDbParam): Integer; overload;
    function NextId(const ASequence: string): Int64;
  end;

  TDbConfig = record
    Host: string;
    Port: Integer;
    Database: string;
    User: string;
    Password: string;
  end;

  TDbErrorClass = (dbeOther, dbeConcurrency, dbeDuplicate, dbeIntegrity);

  { Leitor comum: TSQLQuery (FPC) e TFDQuery (Delphi) são ambos TDataSet. }
  TDataSetReader = class(TInterfacedObject, IDbReader)
  private
    FDataSet: TDataSet;
    function Field(const AName: string): TField;
  public
    constructor Create(const ADataSet: TDataSet);
    destructor Destroy; override;
    function Eof: Boolean;
    procedure Next;
    function Int(const AField: string): Int64;
    function Str(const AField: string): string;
    function Money(const AField: string): TMoney;
    function Qty(const AField: string): TQuantity;
    function Date(const AField: string): TDateTime;
    function Bool(const AField: string): Boolean;
    function IsNull(const AField: string): Boolean;
    function FieldCount: Integer;
    function FieldName(const AIndex: Integer): string;
    function DisplayText(const AIndex: Integer): string;
  end;

function P(const AName: string; const AValue: Int64): TDbParam; overload;
function P(const AName, AValue: string): TDbParam; overload;
function P(const AName: string; const AValue: TMoney): TDbParam; overload;
function P(const AName: string; const AValue: TQuantity): TDbParam; overload;
function PBool(const AName: string; const AValue: Boolean): TDbParam;
function PDateTime(const AName: string; const AValue: TDateTime): TDbParam;
function PDateOnly(const AName: string; const AValue: TDateTime): TDbParam;
function PNull(const AName: string): TDbParam;
{ Zero vira NULL: é como FK opcional chega dos formulários. }
function PIdOrNull(const AName: string; const AValue: Int64): TDbParam;
function PTextOrNull(const AName, AValue: string): TDbParam;

{ Classifica erro do Firebird pelo código GDS e, como reserva, pelo texto. }
function ClassifyFirebirdError(const ACode: Int64; const AMessage: string): TDbErrorClass;
procedure RaiseMappedError(const ACode: Int64; const AMessage: string);

const
  { Tempo máximo esperando um registro bloqueado por outra transação. }
  CLockTimeoutSeconds = 5;

implementation

uses
  EF.Domain.Exceptions;

function NewParam(const AName: string; const AKind: TDbParamKind): TDbParam;
begin
  Result.Name := AName;
  Result.Kind := AKind;
  Result.IntValue := 0;
  Result.TextValue := '';
  Result.CurrencyValue := 0;
  Result.DateValue := 0;
  Result.BoolValue := False;
end;

function P(const AName: string; const AValue: Int64): TDbParam;
begin
  Result := NewParam(AName, dpkInt);
  Result.IntValue := AValue;
end;

function P(const AName, AValue: string): TDbParam;
begin
  Result := NewParam(AName, dpkText);
  Result.TextValue := AValue;
end;

function P(const AName: string; const AValue: TMoney): TDbParam;
begin
  Result := NewParam(AName, dpkCurrency);
  Result.CurrencyValue := AValue.ToCurrency;
end;

function P(const AName: string; const AValue: TQuantity): TDbParam;
begin
  Result := NewParam(AName, dpkCurrency);
  Result.CurrencyValue := AValue.ToCurrency;
end;

function PBool(const AName: string; const AValue: Boolean): TDbParam;
begin
  Result := NewParam(AName, dpkBool);
  Result.BoolValue := AValue;
end;

function PDateTime(const AName: string; const AValue: TDateTime): TDbParam;
begin
  Result := NewParam(AName, dpkDateTime);
  Result.DateValue := AValue;
end;

function PDateOnly(const AName: string; const AValue: TDateTime): TDbParam;
begin
  Result := NewParam(AName, dpkDate);
  Result.DateValue := Trunc(AValue);
end;

function PNull(const AName: string): TDbParam;
begin
  Result := NewParam(AName, dpkNull);
end;

function PIdOrNull(const AName: string; const AValue: Int64): TDbParam;
begin
  if AValue = 0 then
    Result := PNull(AName)
  else
    Result := P(AName, AValue);
end;

function PTextOrNull(const AName, AValue: string): TDbParam;
begin
  if Trim(AValue) = '' then
    Result := PNull(AName)
  else
    Result := P(AName, AValue);
end;

function ClassifyFirebirdError(const ACode: Int64; const AMessage: string): TDbErrorClass;
var
  LText: string;
begin
  case ACode of
    335544336, // isc_deadlock
    335544345, // isc_lock_conflict
    335544510, // isc_lock_timeout
    335544878: // isc_concurrent_transaction
      Exit(dbeConcurrency);
    335544349, // isc_no_dup
    335544665: // isc_unique_key_violation
      Exit(dbeDuplicate);
    335544347, // isc_not_valid
    335544466, // isc_foreign_key
    335544517, // isc_except
    335544558: // isc_check_constraint
      Exit(dbeIntegrity);
  end;
  LText := LowerCase(AMessage);
  if (Pos('deadlock', LText) > 0) or (Pos('lock conflict', LText) > 0) or (Pos('concurrent transaction', LText) > 0) or (Pos('update conflicts', LText) > 0) then
    Result := dbeConcurrency
  else if (Pos('unique key', LText) > 0) or (Pos('duplicate value', LText) > 0) then
    Result := dbeDuplicate
  else if (Pos('check constraint', LText) > 0) or (Pos('foreign key', LText) > 0) or (Pos('exception ', LText) > 0) then
    Result := dbeIntegrity
  else
    Result := dbeOther;
end;

procedure RaiseMappedError(const ACode: Int64; const AMessage: string);
begin
  case ClassifyFirebirdError(ACode, AMessage) of
    dbeConcurrency:
      raise EConcurrencyConflict.Create('O registro está em uso por outro usuário. Aguarde e tente novamente.');
    dbeDuplicate:
      raise EDuplicateKey.Create(AMessage);
    dbeIntegrity:
      raise EIntegrityViolation.Create(AMessage);
  end;
end;

{ TDataSetReader }

constructor TDataSetReader.Create(const ADataSet: TDataSet);
begin
  inherited Create;
  FDataSet := ADataSet;
end;

destructor TDataSetReader.Destroy;
begin
  FDataSet.Free;
  inherited;
end;

procedure EnsureMeasured(const AField: TField);
begin
  { Valor ilegível não pode virar zero: um limite de crédito lido como zero aprova ou
    recusa venda em silêncio. Dinheiro e quantidade são NOT NULL no schema, então NULL
    aqui é erro de consulta ou de driver (docs/adr/004). }
  if AField.IsNull then
    raise EDatabaseError.CreateFmt('Valor nulo ou ilegível em "%s": confira o tipo devolvido pela consulta.', [AField.FieldName]);
end;

function TDataSetReader.Field(const AName: string): TField;
begin
  Result := FDataSet.FieldByName(AName);
end;

function TDataSetReader.Eof: Boolean;
begin
  Result := FDataSet.Eof;
end;

procedure TDataSetReader.Next;
begin
  FDataSet.Next;
end;

function TDataSetReader.Int(const AField: string): Int64;
begin
  Result := Field(AField).AsLargeInt;
end;

function TDataSetReader.Str(const AField: string): string;
begin
  Result := Field(AField).AsString;
end;

function TDataSetReader.Money(const AField: string): TMoney;
begin
  EnsureMeasured(Field(AField));
  Result := TMoney.FromCurrency(Field(AField).AsCurrency);
end;

function TDataSetReader.Qty(const AField: string): TQuantity;
begin
  EnsureMeasured(Field(AField));
  Result := TQuantity.FromCurrency(Field(AField).AsCurrency);
end;

function TDataSetReader.Date(const AField: string): TDateTime;
begin
  Result := Field(AField).AsDateTime;
end;

function TDataSetReader.Bool(const AField: string): Boolean;
begin
  Result := Field(AField).AsBoolean;
end;

function TDataSetReader.IsNull(const AField: string): Boolean;
begin
  Result := Field(AField).IsNull;
end;

function TDataSetReader.FieldCount: Integer;
begin
  Result := FDataSet.FieldCount;
end;

function TDataSetReader.FieldName(const AIndex: Integer): string;
begin
  Result := FDataSet.Fields[AIndex].FieldName;
end;

function TDataSetReader.DisplayText(const AIndex: Integer): string;
var
  LField: TField;
begin
  LField := FDataSet.Fields[AIndex];
  if LField.IsNull then
    Exit('');
  case LField.DataType of
    ftBCD, ftFMTBcd, ftCurrency:
      if LField.Size = 3 then
        Result := TQuantity.FromCurrency(LField.AsCurrency).ToText
      else
        Result := TMoney.FromCurrency(LField.AsCurrency).ToDisplay;
    ftDate:
      Result := FormatDateTime('dd"/"mm"/"yyyy', LField.AsDateTime);
    ftDateTime, ftTimeStamp:
      Result := FormatDateTime('dd"/"mm"/"yyyy hh":"nn', LField.AsDateTime);
    ftBoolean:
      if LField.AsBoolean then
        Result := 'Sim'
      else
        Result := 'Não';
  else
    Result := LField.AsString;
  end;
end;

end.
