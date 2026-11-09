unit EF.Tests.Platform;

{$I EF.inc}
{$M+}

interface

uses
  SysUtils, Classes, DUnitX.TestFramework;

type
  TMigratorTests = class(TObject)
  published
    procedure SplitRespectsStringsCommentsAndSetTerm;
    procedure EditedMigrationIsRefused;
    procedure RunningTwiceAppliesNothing;
  end;

  TAuthTests = class(TObject)
  published
    procedure ValidCredentialsLoadPermissions;
    procedure WrongPasswordAndUnknownUserGiveSameMessage;
    procedure FifthFailureLocksAndLockExpires;
    procedure SuccessfulLoginClearsFailures;
    procedure PasswordIsStoredHashedAndCanBeChanged;
  end;

  TCatalogTests = class(TObject)
  published
    procedure InvalidDocumentIsRefused;
    procedure DuplicateSkuGivesClearMessage;
    procedure PriceChangeIsAudited;
    procedure CreditLimitChangeIsAudited;
    procedure DocumentIsStoredAsDigits;
  end;

  TReportingTests = class(TObject)
  published
    procedure CsvEscapesAndHasBom;
    procedure EveryReadModelQueryRuns;
    procedure NoReportStatementLeavesTransactionOpen;
    procedure UnreadableMoneyFailsInsteadOfBecomingZero;
    procedure UnreadableQuantityFailsInsteadOfBecomingZero;
  end;

  TLoggingTests = class(TObject)
  published
    procedure WritesOneJsonLinePerEventAndRedacts;
  end;

implementation

uses
  EF.Application.Ports, EF.Application.Catalog,
  EF.Domain.Money, EF.Domain.Quantity,
  EF.Infrastructure.Composition, EF.Infrastructure.Database, EF.Infrastructure.Database.Driver,
  EF.Infrastructure.Database.Migrator, EF.Infrastructure.Reporting, EF.Infrastructure.UnitOfWork,
  EF.Shared.Crypto, EF.Shared.Logging, EF.Shared.Text,
  EF.Tests.Support;

function TempDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'ef_' + NewCorrelationId;
  ForceDirectories(Result);
end;

procedure WriteText(const APath, AText: string);
var
  LLines: TStringList;
begin
  LLines := TStringList.Create;
  try
    LLines.Text := AText;
    LLines.SaveToFile(APath);
  finally
    LLines.Free;
  end;
end;

procedure TMigratorTests.SplitRespectsStringsCommentsAndSetTerm;
var
  LStatements: TStatementList;
begin
  LStatements := SplitSqlScript(
    '-- comentário; com ponto e vírgula'#10 +
    'INSERT INTO a VALUES (''x;y'');'#10 +
    '/* bloco; aqui */ INSERT INTO b VALUES (''it''''s'');'#10 +
    'SET TERM ^ ;'#10 +
    'CREATE TRIGGER t FOR a ACTIVE BEFORE INSERT AS BEGIN x = 1; y = 2; END^'#10 +
    'SET TERM ; ^'#10 +
    'COMMIT;');
  Assert.AreEqual(4, Length(LStatements));
  Assert.AreEqual('INSERT INTO a VALUES (''x;y'')', LStatements[0]);
  Assert.AreEqual('INSERT INTO b VALUES (''it''''s'')', LStatements[1]);
  Assert.IsTrue(Pos('x = 1; y = 2; END', LStatements[2]) > 0, 'Corpo do trigger inteiro');
  Assert.AreEqual('COMMIT', LStatements[3]);
end;

function FreshDatabaseConfig(const AEnv: ITestEnv): TDbConfig;
begin
  Result := AEnv.Config;
  Result.Database := ExtractFilePath(Result.Database) + 'mig_' + Copy(NewCorrelationId, 1, 8) + '.fdb';
  CreateDatabase(Result);
end;

procedure TMigratorTests.EditedMigrationIsRefused;
var
  LEnv: ITestEnv;
  LConfig: TDbConfig;
  LDir: string;
  LMigrator: TMigrator;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LConfig := FreshDatabaseConfig(LEnv);
  try
    LDir := TempDir;
    WriteText(LDir + PathDelim + '001_a.sql', 'CREATE TABLE t_a (id INTEGER);');
    LMigrator := TMigrator.Create(OpenSession(LConfig));
    try
      Assert.AreEqual(1, LMigrator.Migrate(LDir));
      WriteText(LDir + PathDelim + '001_a.sql', 'CREATE TABLE t_a (id BIGINT);');
      LRaised := '';
      try
        LMigrator.Migrate(LDir);
      except
        on E: Exception do
          LRaised := E.ClassName;
      end;
      Assert.AreEqual('EMigrationError', LRaised);
    finally
      LMigrator.Free;
    end;
  finally
    DeleteFile(LConfig.Database);
  end;
end;

procedure TMigratorTests.RunningTwiceAppliesNothing;
var
  LEnv: ITestEnv;
  LConfig: TDbConfig;
  LDir: string;
  LMigrator: TMigrator;
begin
  LEnv := NewTestEnv;
  LConfig := FreshDatabaseConfig(LEnv);
  try
    LDir := TempDir;
    WriteText(LDir + PathDelim + '001_a.sql', 'CREATE TABLE t_a (id INTEGER);');
    WriteText(LDir + PathDelim + '002_b.sql', 'INSERT INTO t_a (id) VALUES (1);');
    LMigrator := TMigrator.Create(OpenSession(LConfig));
    try
      Assert.AreEqual(2, LMigrator.Migrate(LDir));
      Assert.AreEqual(0, LMigrator.Migrate(LDir));
    finally
      LMigrator.Free;
    end;
  finally
    DeleteFile(LConfig.Database);
  end;
end;

function RegisterUser(const AEnv: ITestEnv; const APassword: string): string;
begin
  Result := 'login' + Copy(NewCorrelationId, 1, 20);
  AEnv.App.Auth.CreateUser(AEnv.App.Context, Result, 'Usuária de teste', APassword, ['VENDAS']);
end;

function TryLogin(const AEnv: ITestEnv; const AClock: IClock; const AUser, APassword: string; out AMessage: string): Boolean;
var
  LAuth: TAuthService;
begin
  LAuth := TAuthService.Create(NewAuthUow(AEnv.App.Session), AClock);
  try
    Result := True;
    AMessage := '';
    try
      LAuth.Login(AUser, APassword);
    except
      on E: Exception do
      begin
        Result := False;
        AMessage := E.Message;
      end;
    end;
  finally
    LAuth.Free;
  end;
end;

procedure TAuthTests.ValidCredentialsLoadPermissions;
var
  LEnv: ITestEnv;
  LUser: string;
  LAuth: TAuthService;
  LContext: TUserContext;
begin
  LEnv := NewTestEnv;
  LUser := RegisterUser(LEnv, 'senha-forte-1');
  LAuth := TAuthService.Create(NewAuthUow(LEnv.App.Session), LEnv.App.Clock);
  try
    LContext := LAuth.Login(LUser, 'senha-forte-1');
  finally
    LAuth.Free;
  end;
  Assert.IsTrue(LContext.Has(PermOrderConfirm), 'Papel VENDAS confirma pedido');
  Assert.IsFalse(LContext.Has(PermReceivableReverse), 'Papel VENDAS não estorna');
  Assert.IsFalse(LContext.Has(PermStockAdjustApprove), 'Papel VENDAS não aprova ajuste');
end;

procedure TAuthTests.WrongPasswordAndUnknownUserGiveSameMessage;
var
  LEnv: ITestEnv;
  LUser, LWrong, LUnknown: string;
begin
  LEnv := NewTestEnv;
  LUser := RegisterUser(LEnv, 'senha-forte-1');
  Assert.IsFalse(TryLogin(LEnv, LEnv.App.Clock, LUser, 'errada', LWrong));
  Assert.IsFalse(TryLogin(LEnv, LEnv.App.Clock, 'ninguem-aqui', 'errada', LUnknown));
  Assert.AreEqual(LWrong, LUnknown);
end;

procedure TAuthTests.FifthFailureLocksAndLockExpires;
var
  LEnv: ITestEnv;
  LUser, LMessage: string;
  LClock: TFixedClock;
  LClockRef: IClock;
  LIndex: Integer;
begin
  LEnv := NewTestEnv;
  LUser := RegisterUser(LEnv, 'senha-forte-1');
  LClock := TFixedClock.Create(EncodeDate(2026, 3, 10) + EncodeTime(10, 0, 0, 0));
  LClockRef := LClock;
  for LIndex := 1 to CMaxLoginAttempts do
    Assert.IsFalse(TryLogin(LEnv, LClockRef, LUser, 'errada', LMessage));
  Assert.IsFalse(TryLogin(LEnv, LClockRef, LUser, 'senha-forte-1', LMessage), 'Senha certa também é recusada durante o bloqueio');
  Assert.IsTrue(Pos('bloqueado', LMessage) > 0, LMessage);
  LClock.Value := LClock.Value + (CLockMinutes + 1) / (24 * 60);
  Assert.IsTrue(TryLogin(LEnv, LClockRef, LUser, 'senha-forte-1', LMessage), 'Bloqueio expira: ' + LMessage);
end;

procedure TAuthTests.SuccessfulLoginClearsFailures;
var
  LEnv: ITestEnv;
  LUser, LMessage: string;
  LIndex: Integer;
begin
  LEnv := NewTestEnv;
  LUser := RegisterUser(LEnv, 'senha-forte-1');
  for LIndex := 1 to CMaxLoginAttempts - 1 do
    TryLogin(LEnv, LEnv.App.Clock, LUser, 'errada', LMessage);
  Assert.IsTrue(TryLogin(LEnv, LEnv.App.Clock, LUser, 'senha-forte-1', LMessage), LMessage);
  Assert.AreEqual('0', LEnv.QueryText('SELECT failed_attempts FROM users WHERE username = :u', [P('u', LUser)]));
end;

procedure TAuthTests.PasswordIsStoredHashedAndCanBeChanged;
var
  LEnv: ITestEnv;
  LUser, LMessage, LHash: string;
  LAuth: TAuthService;
  LContext: TUserContext;
begin
  LEnv := NewTestEnv;
  LUser := RegisterUser(LEnv, 'senha-forte-1');
  LHash := LEnv.QueryText('SELECT password_hash FROM users WHERE username = :u', [P('u', LUser)]);
  Assert.AreEqual(64, Length(LHash));
  Assert.IsTrue(Pos('senha-forte-1', LHash) = 0);
  LAuth := TAuthService.Create(NewAuthUow(LEnv.App.Session), LEnv.App.Clock);
  try
    LContext := LAuth.Login(LUser, 'senha-forte-1');
    LAuth.ChangePassword(LContext, 'senha-forte-1', 'outra-senha-2');
  finally
    LAuth.Free;
  end;
  Assert.IsFalse(TryLogin(LEnv, LEnv.App.Clock, LUser, 'senha-forte-1', LMessage), 'Senha antiga deixa de valer');
  Assert.IsTrue(TryLogin(LEnv, LEnv.App.Clock, LUser, 'outra-senha-2', LMessage), LMessage);
end;

function ValidCustomer(const ADocument: string): TCustomerRecord;
begin
  Result.Id := 0;
  Result.Name := 'Cliente';
  Result.Document := ADocument;
  Result.Email := '';
  Result.Phone := '';
  Result.CreditLimit := TMoney.Parse('10,00');
  Result.IsActive := True;
end;

procedure TCatalogTests.InvalidDocumentIsRefused;
var
  LEnv: ITestEnv;
  LRaised: string;
begin
  LEnv := NewTestEnv;
  LRaised := '';
  try
    LEnv.App.Catalog.SaveCustomer(ValidCustomer('111.111.111-11'));
  except
    on E: Exception do
      LRaised := E.ClassName;
  end;
  Assert.AreEqual('EValidationError', LRaised);
end;

procedure TCatalogTests.DuplicateSkuGivesClearMessage;
var
  LEnv: ITestEnv;
  LProductId: Int64;
  LProduct: TProductRecord;
  LMessage: string;
begin
  LEnv := NewTestEnv;
  LProductId := LEnv.NewProduct('1,00');
  LEnv.App.Uow.StartTransaction;
  try
    LEnv.App.Uow.Catalog.ReadProduct(LProductId, LProduct);
    LEnv.App.Uow.Commit;
  except
    LEnv.App.Uow.Rollback;
    raise;
  end;
  LProduct.Id := 0;
  LMessage := '';
  try
    LEnv.App.Catalog.SaveProduct(LProduct);
  except
    on E: Exception do
      LMessage := E.Message;
  end;
  Assert.IsTrue(Pos('Já existe produto com o SKU', LMessage) > 0, LMessage);
end;

procedure TCatalogTests.PriceChangeIsAudited;
var
  LEnv: ITestEnv;
  LProductId: Int64;
  LProduct: TProductRecord;
  LDetails: string;
begin
  LEnv := NewTestEnv;
  LProductId := LEnv.NewProduct('10,00');
  LEnv.App.Uow.StartTransaction;
  try
    LEnv.App.Uow.Catalog.ReadProduct(LProductId, LProduct);
    LEnv.App.Uow.Commit;
  except
    LEnv.App.Uow.Rollback;
    raise;
  end;
  LProduct.SalePrice := TMoney.Parse('12,50');
  LEnv.App.Catalog.SaveProduct(LProduct);
  LDetails := LEnv.QueryText('SELECT details FROM audit_events WHERE action = ''product.updated'' AND entity_id = :id', [P('id', LProductId)]);
  Assert.AreEqual('{"sale_price_from":"10.00","sale_price_to":"12.50"}', LDetails);
end;

procedure TCatalogTests.CreditLimitChangeIsAudited;
var
  LEnv: ITestEnv;
  LCustomerId: Int64;
  LCustomer: TCustomerRecord;
begin
  LEnv := NewTestEnv;
  LCustomerId := LEnv.NewCustomer('100,00');
  LEnv.App.Uow.StartTransaction;
  try
    LEnv.App.Uow.Catalog.ReadCustomer(LCustomerId, LCustomer);
    LEnv.App.Uow.Commit;
  except
    LEnv.App.Uow.Rollback;
    raise;
  end;
  LCustomer.CreditLimit := TMoney.Parse('250,00');
  LEnv.App.Catalog.SaveCustomer(LCustomer);
  Assert.AreEqual('{"from":"100.00","to":"250.00"}', LEnv.QueryText(
    'SELECT details FROM audit_events WHERE action = ''customer.credit_limit_changed'' AND entity_id = :id', [P('id', LCustomerId)]));
end;

procedure TCatalogTests.DocumentIsStoredAsDigits;
var
  LEnv: ITestEnv;
  LCustomerId: Int64;
begin
  LEnv := NewTestEnv;
  LEnv.ExecuteSql('DELETE FROM customers WHERE document = ''52998224725''', []);
  LCustomerId := LEnv.App.Catalog.SaveCustomer(ValidCustomer('529.982.247-25'));
  Assert.AreEqual('52998224725', LEnv.QueryText('SELECT document FROM customers WHERE id = :id', [P('id', LCustomerId)]));
end;

procedure TReportingTests.CsvEscapesAndHasBom;
var
  LTable: TDataTable;
  LCsv: RawByteString;
begin
  SetLength(LTable.Columns, 2);
  LTable.Columns[0] := 'Nome';
  LTable.Columns[1] := 'Obs';
  SetLength(LTable.Rows, 1);
  SetLength(LTable.Rows[0], 2);
  LTable.Rows[0][0] := 'Cabo; 2,5mm';
  LTable.Rows[0][1] := 'diz "ok"';
  LCsv := DataTableToCsv(LTable);
  Assert.AreEqual(#$EF#$BB#$BF, Copy(string(LCsv), 1, 3), 'BOM para o Excel');
  Assert.IsTrue(Pos('"Cabo; 2,5mm";"diz ""ok"""', string(LCsv)) > 0, string(LCsv));
end;

procedure TReportingTests.EveryReadModelQueryRuns;
var
  LEnv: ITestEnv;
  LModel: IReadModel;
begin
  { Toda query dos relatórios é preparada pelo Firebird de verdade: erro de SQL falha aqui. }
  LEnv := NewTestEnv;
  LModel := LEnv.App.ReadModel;
  LModel.Products('cabo');
  LModel.Customers('a');
  LModel.Parties(pkSupplier);
  LModel.Parties(pkCarrier);
  LModel.Warehouses;
  LModel.Locations(1);
  LModel.Categories;
  Assert.IsTrue(Length(LModel.Units.Rows) >= 4);
  LModel.StockBalances('');
  LModel.LowStock;
  LModel.Kardex(1, 1);
  LModel.StockReconciliation;
  LModel.PendingAdjustments;
  LModel.SalesOrders('');
  LModel.SalesOrders('RESERVED');
  LModel.SalesOrderItems(1);
  LModel.SalesOrderHistory(1);
  LModel.PurchaseOrders;
  LModel.PurchaseOrderItems(1);
  LModel.PurchaseDivergences;
  LModel.OpenInstallments(Date, False);
  LModel.OpenInstallments(Date, True);
  LModel.Settlements(1);
  LModel.CashFlow(Date - 30, Date + 30);
  LModel.OutboxQueue;
  LModel.IntegrationLog;
  LModel.AuditTrail('', 0);
  LModel.AuditTrail('sales_order', 1);
  LModel.MetricsSummary;
  Assert.Pass;
end;

procedure TReportingTests.NoReportStatementLeavesTransactionOpen;
var
  LEnv: ITestEnv;
begin
  LEnv := NewTestEnv;
  LEnv.App.ReadModel.SalesOrders('');
  Assert.IsFalse(LEnv.App.Session.InTransaction, 'Tela aberta não pode segurar transação');
end;

procedure TReportingTests.UnreadableMoneyFailsInsteadOfBecomingZero;
var
  LEnv: ITestEnv;
  LRaised: Boolean;
begin
  { Firebird 4+: SUM de NUMERIC(18,2) é INT128, que o driver entrega como NULL. Sem a guarda,
    o limite de crédito lia exposição zero e aprovava toda venda. }
  LEnv := NewTestEnv;
  LRaised := False;
  try
    LEnv.QueryMoney('SELECT SUM(CAST(1.50 AS NUMERIC(18,2))) AS s FROM RDB$DATABASE', []);
  except
    on E: Exception do
      LRaised := Pos('ilegível', E.Message) > 0;
  end;
  Assert.IsTrue(LRaised, 'Valor ilegível deve falhar, nunca virar zero');
  Assert.AreEqual('1.50', LEnv.QueryMoney('SELECT CAST(SUM(CAST(1.50 AS NUMERIC(18,2))) AS NUMERIC(18,2)) AS s FROM RDB$DATABASE', []));
end;

procedure TReportingTests.UnreadableQuantityFailsInsteadOfBecomingZero;
var
  LEnv: ITestEnv;
  LReader: IDbReader;
  LRaised: Boolean;
begin
  LEnv := NewTestEnv;
  LEnv.Db.StartTransaction;
  try
    LReader := LEnv.Db.Query('SELECT CAST(NULL AS NUMERIC(15,3)) AS q FROM RDB$DATABASE');
    LRaised := False;
    try
      LReader.Qty('q');
    except
      on E: Exception do
        LRaised := True;
    end;
    LReader := nil;
    LEnv.Db.Commit;
  except
    LEnv.Db.Rollback;
    raise;
  end;
  Assert.IsTrue(LRaised);
end;

procedure TLoggingTests.WritesOneJsonLinePerEventAndRedacts;
var
  LPath: string;
  LLogger: ILogger;
  LLines: TStringList;
begin
  LPath := IncludeTrailingPathDelimiter(TempDir) + 'app.log';
  LLogger := TJsonFileLogger.Create(LPath);
  LLogger.Log(llInfo, 'teste.um', 'corr-1', '{"order_id":7}');
  LLogger.Log(llWarn, 'teste.dois', 'corr-2', '{"password":"segredo"}');
  LLines := TStringList.Create;
  try
    LLines.LoadFromFile(LPath);
    Assert.AreEqual(2, LLines.Count);
    Assert.IsTrue(Pos('"event":"teste.um","correlation_id":"corr-1","fields":{"order_id":7}}', LLines[0]) > 0, LLines[0]);
    Assert.IsTrue(Pos('segredo', LLines[1]) = 0, 'Segredo não vai ao disco: ' + LLines[1]);
    Assert.IsTrue(Pos('"level":"warn"', LLines[1]) > 0, LLines[1]);
  finally
    LLines.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMigratorTests);
  TDUnitX.RegisterTestFixture(TAuthTests);
  TDUnitX.RegisterTestFixture(TCatalogTests);
  TDUnitX.RegisterTestFixture(TReportingTests);
  TDUnitX.RegisterTestFixture(TLoggingTests);

end.
