unit EF.Tests.Support;

{$I EF.inc}

interface

uses
  SysUtils, Classes, SyncObjs,
  EF.Application.Ports, EF.Application.Sales, EF.Domain.Quantity, EF.Domain.Money,
  EF.Infrastructure.Database, EF.Infrastructure.Composition, EF.Shared.Logging;

type
  TFixedClock = class(TInterfacedObject, IClock)
  public
    Value: TDateTime;
    constructor Create(const AValue: TDateTime);
    function Now: TDateTime;
    function Today: TDateTime;
  end;

  ITestEnv = interface
    function App: TAppServices;
    function Db: IDbSession;
    function Config: TDbConfig;
    function NewApp(const ACtx: TUserContext): TAppServices;
    function NewUser(const APermissions: array of string): TUserContext;
    function NewProduct(const APrice: string; const AFractional: Boolean = False): Int64;
    function NewCustomer(const ALimit: string = '1000000,00'): Int64;
    function NewSupplier: Int64;
    function NewWarehouse: Int64;
    procedure AddStock(const AProductId, AWarehouseId: Int64; const AQuantity: string);
    function Balance(const AProductId, AWarehouseId: Int64): string;
    function CountRows(const ASql: string): Integer; overload;
    function CountRows(const ASql: string; const AParams: array of TDbParam): Integer; overload;
    function QueryText(const ASql: string; const AParams: array of TDbParam): string;
    { Primeira coluna como dinheiro, no formato invariante: 12.50 }
    function QueryMoney(const ASql: string): string; overload;
    function QueryMoney(const ASql: string; const AParams: array of TDbParam): string; overload;
    procedure ExecuteSql(const ASql: string); overload;
    procedure ExecuteSql(const ASql: string; const AParams: array of TDbParam); overload;
    function Key: string;
  end;

  TThreadWork = procedure(const AApp: TAppServices; const AIndex: Integer) of object;

  { Nome da classe da exceção de cada thread; vazio = terminou sem erro. }
  TThreadOutcomes = array of string;

function NewTestEnv: ITestEnv;
function AllPermissions: TTextArray;
function Line(const AProductId, AWarehouseId: Int64; const AQuantity: string): TOrderLineInput;
function Lines(const A: array of TOrderLineInput): TOrderLineInputs;
function OrderCommand(const ACustomerId: Int64; const ALines: array of TOrderLineInput; const AKey: string; const AInstallments: Integer = 1): TNewOrderCommand;
{ Roda AWork em N threads, cada uma com conexão própria, soltas ao mesmo tempo. }
function RunConcurrently(const AEnv: ITestEnv; const ACount: Integer; const AWork: TThreadWork): TThreadOutcomes;
function CountOutcome(const AOutcomes: TThreadOutcomes; const AClassName: string): Integer;
{ Lista os resultados para a mensagem de falha: "quem falhou como" é o que explica uma corrida. }
function DescribeOutcomes(const AOutcomes: TThreadOutcomes): string;
{ Pedido em SHIPPED: pronto para faturar. }
function ShippedOrder(const AEnv: ITestEnv; const ATotalPrice: string; const AInstallments: Integer = 1): Int64;
function FirstInstallmentOf(const AEnv: ITestEnv; const AOrderId: Int64): Int64;

implementation

uses
  EF.Infrastructure.Config, EF.Infrastructure.Database.Driver,
  EF.Infrastructure.UnitOfWork, EF.Application.Inventory, EF.Domain.Exceptions,
  EF.Shared.Text;

type
  TTestEnv = class(TInterfacedObject, ITestEnv)
  private
    FDb: IDbSession;
    FConfig: TDbConfig;
    FApp: TAppServices;
    FAdmin: TUserContext;
  public
    constructor Create;
    destructor Destroy; override;
    function App: TAppServices;
    function Db: IDbSession;
    function Config: TDbConfig;
    function NewApp(const ACtx: TUserContext): TAppServices;
    function NewUser(const APermissions: array of string): TUserContext;
    function NewProduct(const APrice: string; const AFractional: Boolean = False): Int64;
    function NewCustomer(const ALimit: string = '1000000,00'): Int64;
    function NewSupplier: Int64;
    function NewWarehouse: Int64;
    procedure AddStock(const AProductId, AWarehouseId: Int64; const AQuantity: string);
    function Balance(const AProductId, AWarehouseId: Int64): string;
    function CountRows(const ASql: string): Integer; overload;
    function CountRows(const ASql: string; const AParams: array of TDbParam): Integer; overload;
    function QueryText(const ASql: string; const AParams: array of TDbParam): string;
    function QueryMoney(const ASql: string): string; overload;
    function QueryMoney(const ASql: string; const AParams: array of TDbParam): string; overload;
    procedure ExecuteSql(const ASql: string); overload;
    procedure ExecuteSql(const ASql: string; const AParams: array of TDbParam); overload;
    function Key: string;
  end;

  TWorkThread = class(TThread)
  private
    FConfig: TDbConfig;
    FCtx: TUserContext;
    FClock: IClock;
    FWork: TThreadWork;
    FIndex: Integer;
    FReady, FGo: TEvent;
  public
    Outcome: string;
    constructor Create(const AConfig: TDbConfig; const ACtx: TUserContext; const AWork: TThreadWork; const AIndex: Integer; const AReady, AGo: TEvent);
    procedure Execute; override;
  end;

function AllPermissions: TTextArray;
const
  CAll: array [0 .. 14] of string = (PermCatalogManage, PermUsersManage, PermStockMove, PermStockAdjustRequest,
    PermStockAdjustApprove, PermPurchaseManage, PermOrderCreate, PermOrderConfirm, PermOrderCancel, PermOrderFulfill,
    PermInvoiceCreate, PermReceivableSettle, PermReceivableReverse, PermReportsView, PermIntegrationManage);
var
  LIndex: Integer;
begin
  SetLength(Result, Length(CAll));
  for LIndex := 0 to High(CAll) do
    Result[LIndex] := CAll[LIndex];
end;

function CheckDigits(const ABase: string; const AIsCnpj: Boolean): string;
const
  CCnpjWeights: array [1 .. 13] of Integer = (6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2);
var
  LRound, LIndex, LSum, LCheck, LBaseLength: Integer;
begin
  Result := ABase;
  LBaseLength := Length(ABase);
  for LRound := LBaseLength to LBaseLength + 1 do
  begin
    LSum := 0;
    for LIndex := 1 to LRound do
      if AIsCnpj then
        LSum := LSum + (Ord(Result[LIndex]) - Ord('0')) * CCnpjWeights[LIndex + 13 - LRound]
      else
        LSum := LSum + (Ord(Result[LIndex]) - Ord('0')) * (LRound + 2 - LIndex);
    if AIsCnpj then
    begin
      LCheck := LSum mod 11;
      if LCheck < 2 then
        LCheck := 0
      else
        LCheck := 11 - LCheck;
    end
    else
    begin
      LCheck := (LSum * 10) mod 11;
      if LCheck = 10 then
        LCheck := 0;
    end;
    Result := Result + IntToStr(LCheck);
  end;
end;

constructor TFixedClock.Create(const AValue: TDateTime);
begin
  inherited Create;
  Value := AValue;
end;

function TFixedClock.Now: TDateTime;
begin
  Result := Value;
end;

function TFixedClock.Today: TDateTime;
begin
  Result := Trunc(Value);
end;

constructor TTestEnv.Create;
begin
  inherited Create;
  if not DbConfigFromEnvironment('EF_TEST_DB', FConfig) then
    raise Exception.Create('Testes de integração exigem EF_TEST_DB_PATH e EF_TEST_DB_PASSWORD. Use scripts/test.sh.');
  FDb := OpenSession(FConfig);
  FAdmin := NewUser(AllPermissions);
  FApp := NewApp(FAdmin);
end;

destructor TTestEnv.Destroy;
begin
  FApp.Free;
  inherited;
end;

function TTestEnv.App: TAppServices;
begin
  Result := FApp;
end;

function TTestEnv.Db: IDbSession;
begin
  Result := FDb;
end;

function TTestEnv.Config: TDbConfig;
begin
  Result := FConfig;
end;

function TTestEnv.NewApp(const ACtx: TUserContext): TAppServices;
begin
  Result := TAppServices.Create(OpenSession(FConfig), ACtx, TSystemClock.Create, TNullLogger.Create);
end;

function TTestEnv.Key: string;
begin
  Result := NewCorrelationId;
end;

function TTestEnv.NewUser(const APermissions: array of string): TUserContext;
var
  LUow: IUnitOfWork;
  LUser: TUserRecord;
  LIndex: Integer;
begin
  LUow := TUnitOfWork.Create(FDb);
  LUser.Id := 0;
  LUser.Username := 'u' + Copy(Key, 1, 30);
  LUser.FullName := 'Usuário de teste';
  LUser.PasswordHash := 'x';
  LUser.PasswordSalt := 'x';
  LUser.PasswordIterations := 1;
  LUser.FailedAttempts := 0;
  LUser.IsActive := True;
  LUser.IsLocked := False;
  LUser.LockedUntil := 0;
  LUow.StartTransaction;
  try
    Result.UserId := LUow.Users.Insert(LUser);
    LUow.Commit;
  except
    LUow.Rollback;
    raise;
  end;
  Result.Username := LUser.Username;
  Result.CorrelationId := '';
  SetLength(Result.Permissions, Length(APermissions));
  for LIndex := 0 to High(APermissions) do
    Result.Permissions[LIndex] := APermissions[LIndex];
end;

function TTestEnv.NewProduct(const APrice: string; const AFractional: Boolean): Int64;
var
  LProduct: TProductRecord;
begin
  LProduct.Id := 0;
  LProduct.CategoryId := 0;
  LProduct.Sku := Copy(UpperCase(Key), 1, 30);
  LProduct.Name := 'Produto ' + LProduct.Sku;
  if AFractional then
    LProduct.UnitCode := 'M'
  else
    LProduct.UnitCode := 'UN';
  LProduct.SalePrice := TMoney.Parse(APrice);
  LProduct.MinimumStock := TQuantity.Zero;
  LProduct.IsActive := True;
  LProduct.AllowsFraction := AFractional;
  Result := FApp.Catalog.SaveProduct(LProduct);
end;

function SequenceDigits(const ADb: IDbSession; const ASequence: string; const AWidth: Integer): string;
begin
  ADb.StartTransaction;
  try
    Result := IntToStr(ADb.NextId(ASequence) + 100000000);
    ADb.Commit;
  except
    ADb.Rollback;
    raise;
  end;
  while Length(Result) < AWidth do
    Result := '7' + Result;
end;

function TTestEnv.NewCustomer(const ALimit: string): Int64;
var
  LCustomer: TCustomerRecord;
begin
  LCustomer.Id := 0;
  LCustomer.Name := 'Cliente ' + Key;
  LCustomer.Document := CheckDigits(SequenceDigits(FDb, 'seq_customers', 9), False);
  LCustomer.Email := '';
  LCustomer.Phone := '';
  LCustomer.CreditLimit := TMoney.Parse(ALimit);
  LCustomer.IsActive := True;
  Result := FApp.Catalog.SaveCustomer(LCustomer);
end;

function TTestEnv.NewSupplier: Int64;
var
  LParty: TPartyRecord;
begin
  LParty.Id := 0;
  LParty.Kind := pkSupplier;
  LParty.Name := 'Fornecedor ' + Key;
  LParty.Document := CheckDigits(SequenceDigits(FDb, 'seq_suppliers', 12), True);
  LParty.Email := '';
  LParty.Phone := '';
  LParty.IsActive := True;
  Result := FApp.Catalog.SaveParty(LParty);
end;

function TTestEnv.NewWarehouse: Int64;
var
  LWarehouse: TWarehouseRecord;
begin
  LWarehouse.Id := 0;
  LWarehouse.Code := Copy(UpperCase(Key), 1, 8);
  LWarehouse.Name := 'Depósito ' + LWarehouse.Code;
  LWarehouse.IsActive := True;
  Result := FApp.Catalog.SaveWarehouse(LWarehouse);
end;

procedure TTestEnv.AddStock(const AProductId, AWarehouseId: Int64; const AQuantity: string);
var
  LOrderId: Int64;
  LLines: TPurchaseLineInputs;
  LReceipt: TReceiptLineInputs;
begin
  { Pela porta da frente: compra e recebimento, como o estoque real entra. }
  SetLength(LLines, 1);
  LLines[0].ProductId := AProductId;
  LLines[0].Quantity := TQuantity.Parse(AQuantity);
  LLines[0].UnitCost := TMoney.Parse('1,00');
  LOrderId := FApp.Purchases.CreateOrder(NewSupplier, AWarehouseId, LLines, '');
  SetLength(LReceipt, 1);
  LReceipt[0].ItemId := StrToInt64(QueryText('SELECT id FROM purchase_order_items WHERE purchase_order_id = :id', [P('id', LOrderId)]));
  LReceipt[0].Quantity := LLines[0].Quantity;
  LReceipt[0].Note := '';
  FApp.Purchases.Receive(LOrderId, LReceipt, Key, '');
end;

function TTestEnv.Balance(const AProductId, AWarehouseId: Int64): string;
var
  LReader: IDbReader;
begin
  FDb.StartTransaction;
  try
    LReader := FDb.Query('SELECT on_hand, reserved FROM stock_balances WHERE product_id = :p AND warehouse_id = :w', [P('p', AProductId), P('w', AWarehouseId)]);
    if LReader.Eof then
      Result := 'sem saldo'
    else
      Result := LReader.Qty('on_hand').ToText + '/' + LReader.Qty('reserved').ToText;
    LReader := nil;
    FDb.Commit;
  except
    FDb.Rollback;
    raise;
  end;
end;

function TTestEnv.CountRows(const ASql: string): Integer;
var
  LNone: array of TDbParam;
begin
  LNone := nil;
  Result := CountRows(ASql, LNone);
end;

function TTestEnv.QueryMoney(const ASql: string): string;
var
  LNone: array of TDbParam;
begin
  LNone := nil;
  Result := QueryMoney(ASql, LNone);
end;

procedure TTestEnv.ExecuteSql(const ASql: string);
var
  LNone: array of TDbParam;
begin
  LNone := nil;
  ExecuteSql(ASql, LNone);
end;

function TTestEnv.CountRows(const ASql: string; const AParams: array of TDbParam): Integer;
begin
  Result := StrToInt(QueryText('SELECT COUNT(*) AS n FROM (' + ASql + ')', AParams));
end;

function TTestEnv.QueryText(const ASql: string; const AParams: array of TDbParam): string;
var
  LReader: IDbReader;
begin
  FDb.StartTransaction;
  try
    LReader := FDb.Query(ASql, AParams);
    if LReader.Eof then
      Result := ''
    else
      Result := LReader.Str(LReader.FieldName(0));
    LReader := nil;
    FDb.Commit;
  except
    FDb.Rollback;
    raise;
  end;
end;

function TTestEnv.QueryMoney(const ASql: string; const AParams: array of TDbParam): string;
var
  LReader: IDbReader;
begin
  FDb.StartTransaction;
  try
    LReader := FDb.Query(ASql, AParams);
    Result := LReader.Money(LReader.FieldName(0)).ToInvariant;
    LReader := nil;
    FDb.Commit;
  except
    FDb.Rollback;
    raise;
  end;
end;

procedure TTestEnv.ExecuteSql(const ASql: string; const AParams: array of TDbParam);
begin
  FDb.StartTransaction;
  try
    FDb.Execute(ASql, AParams);
    FDb.Commit;
  except
    FDb.Rollback;
    raise;
  end;
end;

function NewTestEnv: ITestEnv;
begin
  Result := TTestEnv.Create;
end;

function Line(const AProductId, AWarehouseId: Int64; const AQuantity: string): TOrderLineInput;
begin
  Result.ProductId := AProductId;
  Result.WarehouseId := AWarehouseId;
  Result.Quantity := TQuantity.Parse(AQuantity);
end;

function Lines(const A: array of TOrderLineInput): TOrderLineInputs;
var
  LIndex: Integer;
begin
  SetLength(Result, Length(A));
  for LIndex := 0 to High(A) do
    Result[LIndex] := A[LIndex];
end;

function OrderCommand(const ACustomerId: Int64; const ALines: array of TOrderLineInput; const AKey: string; const AInstallments: Integer): TNewOrderCommand;
begin
  Result.CustomerId := ACustomerId;
  Result.CarrierId := 0;
  Result.Lines := Lines(ALines);
  Result.Installments := AInstallments;
  Result.IntervalDays := 30;
  Result.IdempotencyKey := AKey;
end;

constructor TWorkThread.Create(const AConfig: TDbConfig; const ACtx: TUserContext; const AWork: TThreadWork; const AIndex: Integer; const AReady, AGo: TEvent);
begin
  FConfig := AConfig;
  FCtx := ACtx;
  FWork := AWork;
  FIndex := AIndex;
  FReady := AReady;
  FGo := AGo;
  FClock := TSystemClock.Create;
  Outcome := 'NaoExecutou';
  inherited Create(False);
end;

procedure TWorkThread.Execute;
var
  LApp: TAppServices;
begin
  try
    LApp := TAppServices.Create(OpenSession(FConfig), FCtx, FClock, TNullLogger.Create);
    try
      FReady.SetEvent;
      FGo.WaitFor(30000);
      FWork(LApp, FIndex);
      Outcome := '';
    finally
      LApp.Free;
    end;
  except
    on E: Exception do
    begin
      Outcome := E.ClassName;
      { Erro de negócio é resultado esperado de uma corrida. O resto precisa aparecer inteiro. }
      if not (E is EDomainError) then
        WriteLn(ErrOutput, 'Erro inesperado na thread ', FIndex, ': ', E.ClassName, ': ', E.Message);
      FReady.SetEvent;
    end;
  end;
end;

function RunConcurrently(const AEnv: ITestEnv; const ACount: Integer; const AWork: TThreadWork): TThreadOutcomes;
var
  LThreads: array of TWorkThread;
  LReady: array of TEvent;
  LGo: TEvent;
  LIndex: Integer;
begin
  LGo := TEvent.Create(nil, True, False, '');
  SetLength(LThreads, ACount);
  SetLength(LReady, ACount);
  try
    for LIndex := 0 to ACount - 1 do
    begin
      LReady[LIndex] := TEvent.Create(nil, True, False, '');
      LThreads[LIndex] := TWorkThread.Create(AEnv.Config, AEnv.App.Context, AWork, LIndex, LReady[LIndex], LGo);
    end;
    { Só solta depois de todas conectadas: a corrida acontece no SQL, não na conexão. }
    for LIndex := 0 to ACount - 1 do
      LReady[LIndex].WaitFor(30000);
    LGo.SetEvent;
    SetLength(Result, ACount);
    for LIndex := 0 to ACount - 1 do
    begin
      LThreads[LIndex].WaitFor;
      Result[LIndex] := LThreads[LIndex].Outcome;
    end;
  finally
    for LIndex := 0 to ACount - 1 do
    begin
      LThreads[LIndex].Free;
      LReady[LIndex].Free;
    end;
    LGo.Free;
  end;
end;

function CountOutcome(const AOutcomes: TThreadOutcomes; const AClassName: string): Integer;
var
  LIndex: Integer;
begin
  Result := 0;
  for LIndex := 0 to High(AOutcomes) do
    if AOutcomes[LIndex] = AClassName then
      Inc(Result);
end;

function DescribeOutcomes(const AOutcomes: TThreadOutcomes): string;
var
  LIndex: Integer;
begin
  Result := '';
  for LIndex := 0 to High(AOutcomes) do
  begin
    if AOutcomes[LIndex] = '' then
      Result := Result + 'sucesso '
    else
      Result := Result + AOutcomes[LIndex] + ' ';
  end;
end;

function ShippedOrder(const AEnv: ITestEnv; const ATotalPrice: string; const AInstallments: Integer): Int64;
var
  LProduct, LWarehouse: Int64;
begin
  LProduct := AEnv.NewProduct(ATotalPrice);
  LWarehouse := AEnv.NewWarehouse;
  AEnv.AddStock(LProduct, LWarehouse, '5');
  Result := AEnv.App.Sales.ConfirmNew(OrderCommand(AEnv.NewCustomer, [Line(LProduct, LWarehouse, '1')], AEnv.Key, AInstallments)).OrderId;
  AEnv.App.Sales.StartPicking(Result);
  AEnv.App.Sales.Ship(Result, 0);
end;

function FirstInstallmentOf(const AEnv: ITestEnv; const AOrderId: Int64): Int64;
begin
  Result := StrToInt64(AEnv.QueryText(
    'SELECT FIRST 1 i.id FROM receivable_installments i JOIN receivable_titles t ON t.id = i.title_id ' +
    'JOIN invoices n ON n.id = t.invoice_id WHERE n.sales_order_id = :order_id ORDER BY i.installment_no',
    [P('order_id', AOrderId)]));
end;

end.
