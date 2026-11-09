unit EF.Infrastructure.Database.FireDAC;

{ Adaptador Delphi (FireDAC). A interface é a mesma do adaptador SQLdb, e toda a SQL é
  compartilhada: só conexão, transação, parâmetros e tradução de erro moram aqui.
  ESTADO: escrito contra a documentação, ainda não compilado (ver docs/verificacao-delphi.md). }

interface

uses
  System.SysUtils, System.Classes, Data.DB,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Stan.Param,
  FireDAC.Phys, FireDAC.Phys.Intf, FireDAC.Phys.FB, FireDAC.DApt, FireDAC.UI.Intf,
  FireDAC.ConsoleUI.Wait, FireDAC.Comp.Client,
  EF.Infrastructure.Database;

type
  TFireDacSession = class(TInterfacedObject, IDbSession)
  private
    FConnection: TFDConnection;
    FTransaction: TFDTransaction;
    function NewQuery(const ASql: string; const AParams: array of TDbParam): TFDQuery;
    procedure RequireTransaction;
    procedure TranslateAndRaise(const AError: Exception);
  public
    constructor Create(const AConfig: TDbConfig);
    destructor Destroy; override;
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

procedure CreateFirebirdDatabase(const AConfig: TDbConfig);
function OpenFirebirdSession(const AConfig: TDbConfig): IDbSession;

implementation

procedure ConfigureConnection(const AConnection: TFDConnection; const AConfig: TDbConfig);
begin
  AConnection.LoginPrompt := False;
  AConnection.ResourceOptions.SilentMode := True;
  AConnection.Params.Clear;
  AConnection.Params.Add('DriverID=FB');
  AConnection.Params.Add('Protocol=TCPIP');
  AConnection.Params.Add('Server=' + AConfig.Host);
  if AConfig.Port > 0 then
    AConnection.Params.Add('Port=' + IntToStr(AConfig.Port));
  AConnection.Params.Add('Database=' + AConfig.Database);
  AConnection.Params.Add('User_Name=' + AConfig.User);
  AConnection.Params.Add('Password=' + AConfig.Password);
  AConnection.Params.Add('CharacterSet=UTF8');
  AConnection.Params.Add('SQLDialect=3');
end;

procedure CreateFirebirdDatabase(const AConfig: TDbConfig);
var
  LConnection: TFDConnection;
begin
  LConnection := TFDConnection.Create(nil);
  try
    ConfigureConnection(LConnection, AConfig);
    LConnection.Params.Add('CreateDatabase=Yes');
    LConnection.Params.Add('PageSize=16384');
    LConnection.Open;
    LConnection.Close;
  finally
    LConnection.Free;
  end;
end;

function OpenFirebirdSession(const AConfig: TDbConfig): IDbSession;
begin
  Result := TFireDacSession.Create(AConfig);
end;

constructor TFireDacSession.Create(const AConfig: TDbConfig);
begin
  inherited Create;
  FConnection := TFDConnection.Create(nil);
  FTransaction := TFDTransaction.Create(nil);
  ConfigureConnection(FConnection, AConfig);
  FConnection.TxOptions.AutoCommit := False;
  FConnection.UpdateOptions.LockWait := True;
  FTransaction.Connection := FConnection;
  FTransaction.Options.AutoCommit := False;
  FTransaction.Options.AutoStart := False;
  FTransaction.Options.AutoStop := False;
  FTransaction.Options.Isolation := xiReadCommitted;
  FTransaction.Options.ReadOnly := False;
  { Mesma política do adaptador SQLdb. Conferir "lock_timeout" na primeira compilação:
    a documentação não detalha este parâmetro (docs/verificacao-delphi.md). }
  FTransaction.Options.Params.Add('read_committed');
  FTransaction.Options.Params.Add('rec_version');
  FTransaction.Options.Params.Add('wait');
  FTransaction.Options.Params.Add('lock_timeout=' + IntToStr(CLockTimeoutSeconds));
  FConnection.Transaction := FTransaction;
  FConnection.UpdateTransaction := FTransaction;
  FConnection.Open;
end;

destructor TFireDacSession.Destroy;
begin
  if FTransaction.Active then
    FTransaction.Rollback;
  FConnection.Close;
  FTransaction.Free;
  FConnection.Free;
  inherited;
end;

procedure TFireDacSession.TranslateAndRaise(const AError: Exception);
var
  LEngine: EFDDBEngineException;
begin
  if AError is EFDDBEngineException then
  begin
    LEngine := EFDDBEngineException(AError);
    if LEngine.ErrorCount > 0 then
      RaiseMappedError(LEngine.Errors[0].ErrorCode, AError.Message)
    else
      RaiseMappedError(0, AError.Message);
  end
  else
    RaiseMappedError(0, AError.Message);
end;

procedure TFireDacSession.StartTransaction;
begin
  if FTransaction.Active then
    raise EDatabaseError.Create('Transação já iniciada nesta sessão.');
  FTransaction.StartTransaction;
end;

procedure TFireDacSession.Commit;
begin
  try
    FTransaction.Commit;
  except
    on E: Exception do
    begin
      TranslateAndRaise(E);
      raise;
    end;
  end;
end;

procedure TFireDacSession.Rollback;
begin
  if FTransaction.Active then
    FTransaction.Rollback;
end;

function TFireDacSession.InTransaction: Boolean;
begin
  Result := FTransaction.Active;
end;

procedure TFireDacSession.RequireTransaction;
begin
  if not FTransaction.Active then
    raise EDatabaseError.Create('SQL fora de transação.');
end;

function TFireDacSession.NewQuery(const ASql: string; const AParams: array of TDbParam): TFDQuery;
var
  LIndex: Integer;
  LParam: TFDParam;
begin
  RequireTransaction;
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConnection;
    Result.Transaction := FTransaction;
    Result.UpdateTransaction := FTransaction;
    Result.UpdateOptions.ReadOnly := True;
    Result.UpdateOptions.RequestLive := False;
    Result.ResourceOptions.MacroCreate := False;
    Result.ResourceOptions.MacroExpand := False;
    Result.ResourceOptions.EscapeExpand := False;
    { Sem parâmetros, ":x" é variável de PSQL (EXECUTE BLOCK), não parâmetro da aplicação. }
    Result.ResourceOptions.ParamCreate := Length(AParams) > 0;
    Result.FetchOptions.Unidirectional := True;
    Result.SQL.Text := ASql;
    for LIndex := Low(AParams) to High(AParams) do
    begin
      LParam := Result.ParamByName(AParams[LIndex].Name);
      case AParams[LIndex].Kind of
        dpkNull:
          begin
            LParam.DataType := ftString;
            LParam.Clear;
          end;
        dpkInt: LParam.AsLargeInt := AParams[LIndex].IntValue;
        dpkText: LParam.AsString := AParams[LIndex].TextValue;
        dpkCurrency: LParam.AsCurrency := AParams[LIndex].CurrencyValue;
        dpkDateTime: LParam.AsDateTime := AParams[LIndex].DateValue;
        dpkDate: LParam.AsDate := AParams[LIndex].DateValue;
        dpkBool: LParam.AsBoolean := AParams[LIndex].BoolValue;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TFireDacSession.Query(const ASql: string): IDbReader;
var
  LNone: array of TDbParam;
begin
  LNone := nil;
  Result := Query(ASql, LNone);
end;

function TFireDacSession.Query(const ASql: string; const AParams: array of TDbParam): IDbReader;
var
  LQuery: TFDQuery;
begin
  LQuery := NewQuery(ASql, AParams);
  try
    LQuery.Open;
    Result := TDataSetReader.Create(LQuery);
  except
    on E: Exception do
    begin
      LQuery.Free;
      TranslateAndRaise(E);
      raise;
    end;
  end;
end;

function TFireDacSession.Execute(const ASql: string): Integer;
var
  LNone: array of TDbParam;
begin
  LNone := nil;
  Result := Execute(ASql, LNone);
end;

function TFireDacSession.Execute(const ASql: string; const AParams: array of TDbParam): Integer;
var
  LQuery: TFDQuery;
begin
  LQuery := NewQuery(ASql, AParams);
  try
    try
      LQuery.ExecSQL;
      Result := LQuery.RowsAffected;
    except
      on E: Exception do
      begin
        TranslateAndRaise(E);
        raise;
      end;
    end;
  finally
    LQuery.Free;
  end;
end;

function TFireDacSession.NextId(const ASequence: string): Int64;
begin
  Result := Query('SELECT NEXT VALUE FOR ' + ASequence + ' AS id FROM RDB$DATABASE').Int('id');
end;

end.
