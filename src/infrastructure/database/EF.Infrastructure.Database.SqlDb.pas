unit EF.Infrastructure.Database.SqlDb;

{ Adaptador Free Pascal (SQLdb). Existe para executar repositórios, SQL e testes de
  integração contra um Firebird real em CI. O produto em Delphi usa o adaptador FireDAC. }

{$I EF.inc}

interface

uses
  SysUtils, Classes, SyncObjs, DB, sqldb, IBConnection,
  EF.Infrastructure.Database;

type
  TSqlDbSession = class(TInterfacedObject, IDbSession)
  private
    FConnection: TIBConnection;
    FTransaction: TSQLTransaction;
    function NewQuery(const ASql: string; const AParams: array of TDbParam): TSQLQuery;
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

var
  { Abrir e fechar conexão mexe em estado global do driver (carga da fbclient por contagem de
    referências). Em paralelo, isso falhou em 1 de cada ~400 corridas com "Invalid clumplet
    buffer structure". A serialização vale só para conectar; o trabalho no banco segue paralelo. }
  GConnectLock: TCriticalSection;

function HostWithPort(const AConfig: TDbConfig): string;
begin
  { Formato clássico do fbclient: host/porta:caminho }
  if AConfig.Port > 0 then
    Result := AConfig.Host + '/' + IntToStr(AConfig.Port)
  else
    Result := AConfig.Host;
end;

procedure ConfigureConnection(const AConnection: TIBConnection; const AConfig: TDbConfig);
begin
  AConnection.HostName := HostWithPort(AConfig);
  AConnection.DatabaseName := AConfig.Database;
  AConnection.UserName := AConfig.User;
  AConnection.Password := AConfig.Password;
  AConnection.CharSet := 'UTF8';
  AConnection.Dialect := 3;
  AConnection.LoginPrompt := False;
end;

procedure CreateFirebirdDatabase(const AConfig: TDbConfig);
var
  LConnection: TIBConnection;
begin
  LConnection := TIBConnection.Create(nil);
  try
    ConfigureConnection(LConnection, AConfig);
    LConnection.Params.Values['PAGE_SIZE'] := '16384';
    GConnectLock.Acquire;
    try
      LConnection.CreateDB;
    finally
      GConnectLock.Release;
    end;
  finally
    LConnection.Free;
  end;
end;

function OpenFirebirdSession(const AConfig: TDbConfig): IDbSession;
begin
  Result := TSqlDbSession.Create(AConfig);
end;

constructor TSqlDbSession.Create(const AConfig: TDbConfig);
begin
  inherited Create;
  FConnection := TIBConnection.Create(nil);
  FTransaction := TSQLTransaction.Create(nil);
  ConfigureConnection(FConnection, AConfig);
  FConnection.Transaction := FTransaction;
  FTransaction.DataBase := FConnection;
  FTransaction.Action := caRollback;
  { READ COMMITTED + WAIT: quem chega depois espera o bloqueio e, ao obtê-lo, lê o valor
    já confirmado. É o que faz a revalidação de saldo enxergar a venda do concorrente. }
  FTransaction.Params.Add('isc_tpb_read_committed');
  FTransaction.Params.Add('isc_tpb_rec_version');
  FTransaction.Params.Add('isc_tpb_write');
  FTransaction.Params.Add('isc_tpb_wait');
  FTransaction.Params.Add('isc_tpb_lock_timeout=' + IntToStr(CLockTimeoutSeconds));
  GConnectLock.Acquire;
  try
    FConnection.Open;
  finally
    GConnectLock.Release;
  end;
end;

destructor TSqlDbSession.Destroy;
begin
  if FTransaction.Active then
    FTransaction.Rollback;
  GConnectLock.Acquire;
  try
    FConnection.Close;
  finally
    GConnectLock.Release;
  end;
  FTransaction.Free;
  FConnection.Free;
  inherited;
end;

procedure TSqlDbSession.TranslateAndRaise(const AError: Exception);
begin
  if AError is ESQLDatabaseError then
    RaiseMappedError(ESQLDatabaseError(AError).ErrorCode, AError.Message)
  else
    RaiseMappedError(0, AError.Message);
end;

procedure TSqlDbSession.StartTransaction;
begin
  if FTransaction.Active then
    raise EDatabaseError.Create('Transação já iniciada nesta sessão.');
  FTransaction.StartTransaction;
end;

procedure TSqlDbSession.Commit;
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

procedure TSqlDbSession.Rollback;
begin
  if FTransaction.Active then
    FTransaction.Rollback;
end;

function TSqlDbSession.InTransaction: Boolean;
begin
  Result := FTransaction.Active;
end;

procedure TSqlDbSession.RequireTransaction;
begin
  { Sem isto, o SQLdb abriria uma transação implícita que ninguém fecharia. }
  if not FTransaction.Active then
    raise EDatabaseError.Create('SQL fora de transação.');
end;

function TSqlDbSession.NewQuery(const ASql: string; const AParams: array of TDbParam): TSQLQuery;
var
  LIndex: Integer;
  LParam: TParam;
begin
  RequireTransaction;
  Result := TSQLQuery.Create(nil);
  try
    Result.DataBase := FConnection;
    Result.Transaction := FTransaction;
    Result.ParseSQL := False;
    Result.ReadOnly := True;
    Result.UsePrimaryKeyAsKey := False;
    { Sem parâmetros, ":x" é variável de PSQL (EXECUTE BLOCK), não parâmetro da aplicação. }
    Result.ParamCheck := Length(AParams) > 0;
    Result.SQL.Text := ASql;
    for LIndex := Low(AParams) to High(AParams) do
    begin
      LParam := Result.Params.ParamByName(AParams[LIndex].Name);
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

function TSqlDbSession.Query(const ASql: string): IDbReader;
var
  LNone: array of TDbParam;
begin
  LNone := nil;
  Result := Query(ASql, LNone);
end;

function TSqlDbSession.Query(const ASql: string; const AParams: array of TDbParam): IDbReader;
var
  LQuery: TSQLQuery;
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

function TSqlDbSession.Execute(const ASql: string): Integer;
var
  LNone: array of TDbParam;
begin
  LNone := nil;
  Result := Execute(ASql, LNone);
end;

function TSqlDbSession.Execute(const ASql: string; const AParams: array of TDbParam): Integer;
var
  LQuery: TSQLQuery;
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

function TSqlDbSession.NextId(const ASequence: string): Int64;
begin
  Result := Query('SELECT NEXT VALUE FOR ' + ASequence + ' AS id FROM RDB$DATABASE').Int('id');
end;

initialization
  GConnectLock := TCriticalSection.Create;

finalization
  GConnectLock.Free;

end.
