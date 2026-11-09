unit EF.Infrastructure.Repositories.Support;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Application.Ports, EF.Infrastructure.Database;

type
  TCatalogRepository = class(TInterfacedObject, ICatalogRepository)
  private
    FDb: IDbSession;
    function ReadCustomerWith(const ASql: string; const AId: Int64; out ACustomer: TCustomerRecord): Boolean;
  public
    constructor Create(const ADb: IDbSession);
    function ReadProduct(const AId: Int64; out AProduct: TProductRecord): Boolean;
    function SaveProduct(const AProduct: TProductRecord): Int64;
    function ReadCustomer(const AId: Int64; out ACustomer: TCustomerRecord): Boolean;
    function LockCustomer(const AId: Int64; out ACustomer: TCustomerRecord): Boolean;
    function SaveCustomer(const ACustomer: TCustomerRecord): Int64;
    function SaveParty(const AParty: TPartyRecord): Int64;
    function SaveWarehouse(const AWarehouse: TWarehouseRecord): Int64;
    function AddLocation(const AWarehouseId: Int64; const ACode, ADescription: string): Int64;
    function AddCategory(const AName: string): Int64;
    function WarehouseIsActive(const AId: Int64): Boolean;
  end;

  TUserRepository = class(TInterfacedObject, IUserRepository)
  private
    FDb: IDbSession;
    function ReadWith(const ASql: string; const AParam: TDbParam; out AUser: TUserRecord): Boolean;
  public
    constructor Create(const ADb: IDbSession);
    function FindByUsername(const AUsername: string; out AUser: TUserRecord): Boolean;
    function ReadUser(const AId: Int64; out AUser: TUserRecord): Boolean;
    function Insert(const AUser: TUserRecord): Int64;
    procedure AssignRole(const AUserId: Int64; const ARoleCode: string);
    procedure SavePassword(const AUserId: Int64; const AHash, ASalt: string; const AIterations: Integer);
    procedure RecordLoginFailure(const AUserId: Int64; const AFailedAttempts: Integer; const AHasLock: Boolean; const ALockedUntil: TDateTime);
    procedure ClearLoginFailures(const AUserId: Int64);
    function PermissionsOf(const AUserId: Int64): TTextArray;
  end;

  TAuditLog = class(TInterfacedObject, IAuditLog)
  private
    FDb: IDbSession;
  public
    constructor Create(const ADb: IDbSession);
    procedure Add(const AUserId: Int64; const AAction, AEntityType: string; const AEntityId: Int64; const ACorrelationId, ADetailsJson: string);
  end;

  TOutboxRepository = class(TInterfacedObject, IOutboxRepository)
  private
    FDb: IDbSession;
  public
    constructor Create(const ADb: IDbSession);
    procedure Enqueue(const AEvent: TOutboxEvent);
    function ClaimDue(const ALimit: Integer; const ANow, AClaimUntil: TDateTime): TOutboxEventArray;
    procedure MarkSent(const AId: Int64; const ANow: TDateTime);
    procedure MarkRetry(const AId: Int64; const ANextAttempt: TDateTime; const AError: string);
    procedure MarkDead(const AId: Int64; const AError: string);
    procedure Requeue(const AId: Int64; const ANow: TDateTime);
  end;

  TIntegrationLogRepository = class(TInterfacedObject, IIntegrationLogRepository)
  private
    FDb: IDbSession;
  public
    constructor Create(const ADb: IDbSession);
    procedure Add(const AEntry: TIntegrationLogEntry);
  end;

  TMetricsRepository = class(TInterfacedObject, IMetricsRepository)
  private
    FDb: IDbSession;
  public
    constructor Create(const ADb: IDbSession);
    procedure Add(const AMetric, ACorrelationId, ADetail: string; const ADurationMs: Int64);
  end;

  TSettingsRepository = class(TInterfacedObject, ISettingsRepository)
  private
    FDb: IDbSession;
  public
    constructor Create(const ADb: IDbSession);
    function GetText(const AKey, ADefault: string): string;
    procedure SetText(const AKey, AValue: string);
  end;

implementation

{ TCatalogRepository }

constructor TCatalogRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

function TCatalogRepository.ReadProduct(const AId: Int64; out AProduct: TProductRecord): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query(
    'SELECT p.id, p.category_id, p.sku, p.name, p.unit_code, p.sale_price, p.minimum_stock, p.is_active, u.allows_fraction ' +
    'FROM products p JOIN units u ON u.code = p.unit_code WHERE p.id = :id', [P('id', AId)]);
  Result := not LReader.Eof;
  if Result then
  begin
    AProduct.Id := LReader.Int('id');
    AProduct.CategoryId := LReader.Int('category_id');
    AProduct.Sku := LReader.Str('sku');
    AProduct.Name := LReader.Str('name');
    AProduct.UnitCode := LReader.Str('unit_code');
    AProduct.SalePrice := LReader.Money('sale_price');
    AProduct.MinimumStock := LReader.Qty('minimum_stock');
    AProduct.IsActive := LReader.Bool('is_active');
    AProduct.AllowsFraction := LReader.Bool('allows_fraction');
  end;
end;

function TCatalogRepository.SaveProduct(const AProduct: TProductRecord): Int64;
begin
  Result := AProduct.Id;
  if Result = 0 then
  begin
    Result := FDb.NextId('seq_products');
    FDb.Execute(
      'INSERT INTO products (id, sku, name, category_id, unit_code, sale_price, minimum_stock, is_active) ' +
      'VALUES (:id, :sku, :name, :category_id, :unit_code, :sale_price, :minimum_stock, :is_active)',
      [P('id', Result), P('sku', AProduct.Sku), P('name', AProduct.Name), PIdOrNull('category_id', AProduct.CategoryId),
       P('unit_code', AProduct.UnitCode), P('sale_price', AProduct.SalePrice), P('minimum_stock', AProduct.MinimumStock), PBool('is_active', AProduct.IsActive)]);
  end
  else
    FDb.Execute(
      'UPDATE products SET sku = :sku, name = :name, category_id = :category_id, unit_code = :unit_code, sale_price = :sale_price, ' +
      'minimum_stock = :minimum_stock, is_active = :is_active, updated_at = LOCALTIMESTAMP WHERE id = :id',
      [P('sku', AProduct.Sku), P('name', AProduct.Name), PIdOrNull('category_id', AProduct.CategoryId), P('unit_code', AProduct.UnitCode),
       P('sale_price', AProduct.SalePrice), P('minimum_stock', AProduct.MinimumStock), PBool('is_active', AProduct.IsActive), P('id', Result)]);
end;

function TCatalogRepository.ReadCustomerWith(const ASql: string; const AId: Int64; out ACustomer: TCustomerRecord): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query(ASql, [P('id', AId)]);
  Result := not LReader.Eof;
  if Result then
  begin
    ACustomer.Id := LReader.Int('id');
    ACustomer.Name := LReader.Str('name');
    ACustomer.Document := LReader.Str('document');
    ACustomer.Email := LReader.Str('email');
    ACustomer.Phone := LReader.Str('phone');
    ACustomer.CreditLimit := LReader.Money('credit_limit');
    ACustomer.IsActive := LReader.Bool('is_active');
  end;
end;

function TCatalogRepository.ReadCustomer(const AId: Int64; out ACustomer: TCustomerRecord): Boolean;
begin
  Result := ReadCustomerWith('SELECT id, name, document, email, phone, credit_limit, is_active FROM customers WHERE id = :id', AId, ACustomer);
end;

function TCatalogRepository.LockCustomer(const AId: Int64; out ACustomer: TCustomerRecord): Boolean;
begin
  Result := ReadCustomerWith('SELECT id, name, document, email, phone, credit_limit, is_active FROM customers WHERE id = :id WITH LOCK', AId, ACustomer);
end;

function TCatalogRepository.SaveCustomer(const ACustomer: TCustomerRecord): Int64;
begin
  Result := ACustomer.Id;
  if Result = 0 then
  begin
    Result := FDb.NextId('seq_customers');
    FDb.Execute(
      'INSERT INTO customers (id, name, document, email, phone, credit_limit, is_active) VALUES (:id, :name, :document, :email, :phone, :credit_limit, :is_active)',
      [P('id', Result), P('name', ACustomer.Name), P('document', ACustomer.Document), PTextOrNull('email', ACustomer.Email),
       PTextOrNull('phone', ACustomer.Phone), P('credit_limit', ACustomer.CreditLimit), PBool('is_active', ACustomer.IsActive)]);
  end
  else
    FDb.Execute(
      'UPDATE customers SET name = :name, document = :document, email = :email, phone = :phone, credit_limit = :credit_limit, ' +
      'is_active = :is_active, updated_at = LOCALTIMESTAMP WHERE id = :id',
      [P('name', ACustomer.Name), P('document', ACustomer.Document), PTextOrNull('email', ACustomer.Email), PTextOrNull('phone', ACustomer.Phone),
       P('credit_limit', ACustomer.CreditLimit), PBool('is_active', ACustomer.IsActive), P('id', Result)]);
end;

function TCatalogRepository.SaveParty(const AParty: TPartyRecord): Int64;
begin
  Result := AParty.Id;
  if AParty.Kind = pkSupplier then
  begin
    if Result = 0 then
    begin
      Result := FDb.NextId('seq_suppliers');
      FDb.Execute(
        'INSERT INTO suppliers (id, name, document, email, phone, is_active) VALUES (:id, :name, :document, :email, :phone, :is_active)',
        [P('id', Result), P('name', AParty.Name), P('document', AParty.Document), PTextOrNull('email', AParty.Email), PTextOrNull('phone', AParty.Phone), PBool('is_active', AParty.IsActive)]);
    end
    else
      FDb.Execute(
        'UPDATE suppliers SET name = :name, document = :document, email = :email, phone = :phone, is_active = :is_active WHERE id = :id',
        [P('name', AParty.Name), P('document', AParty.Document), PTextOrNull('email', AParty.Email), PTextOrNull('phone', AParty.Phone), PBool('is_active', AParty.IsActive), P('id', Result)]);
  end
  else if Result = 0 then
  begin
    Result := FDb.NextId('seq_carriers');
    FDb.Execute(
      'INSERT INTO carriers (id, name, document, phone, is_active) VALUES (:id, :name, :document, :phone, :is_active)',
      [P('id', Result), P('name', AParty.Name), P('document', AParty.Document), PTextOrNull('phone', AParty.Phone), PBool('is_active', AParty.IsActive)]);
  end
  else
    FDb.Execute(
      'UPDATE carriers SET name = :name, document = :document, phone = :phone, is_active = :is_active WHERE id = :id',
      [P('name', AParty.Name), P('document', AParty.Document), PTextOrNull('phone', AParty.Phone), PBool('is_active', AParty.IsActive), P('id', Result)]);
end;

function TCatalogRepository.SaveWarehouse(const AWarehouse: TWarehouseRecord): Int64;
begin
  Result := AWarehouse.Id;
  if Result = 0 then
  begin
    Result := FDb.NextId('seq_warehouses');
    FDb.Execute('INSERT INTO warehouses (id, code, name, is_active) VALUES (:id, :code, :name, :is_active)',
      [P('id', Result), P('code', AWarehouse.Code), P('name', AWarehouse.Name), PBool('is_active', AWarehouse.IsActive)]);
  end
  else
    FDb.Execute('UPDATE warehouses SET code = :code, name = :name, is_active = :is_active WHERE id = :id',
      [P('code', AWarehouse.Code), P('name', AWarehouse.Name), PBool('is_active', AWarehouse.IsActive), P('id', Result)]);
end;

function TCatalogRepository.AddLocation(const AWarehouseId: Int64; const ACode, ADescription: string): Int64;
begin
  Result := FDb.NextId('seq_storage_locations');
  FDb.Execute('INSERT INTO storage_locations (id, warehouse_id, code, description) VALUES (:id, :warehouse_id, :code, :description)',
    [P('id', Result), P('warehouse_id', AWarehouseId), P('code', ACode), PTextOrNull('description', ADescription)]);
end;

function TCatalogRepository.AddCategory(const AName: string): Int64;
begin
  Result := FDb.NextId('seq_categories');
  FDb.Execute('INSERT INTO categories (id, name) VALUES (:id, :name)', [P('id', Result), P('name', AName)]);
end;

function TCatalogRepository.WarehouseIsActive(const AId: Int64): Boolean;
begin
  Result := not FDb.Query('SELECT 1 AS x FROM warehouses WHERE id = :id AND is_active', [P('id', AId)]).Eof;
end;

{ TUserRepository }

constructor TUserRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

function TUserRepository.ReadWith(const ASql: string; const AParam: TDbParam; out AUser: TUserRecord): Boolean;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query(ASql, [AParam]);
  Result := not LReader.Eof;
  if Result then
  begin
    AUser.Id := LReader.Int('id');
    AUser.Username := LReader.Str('username');
    AUser.FullName := LReader.Str('full_name');
    AUser.PasswordHash := LReader.Str('password_hash');
    AUser.PasswordSalt := LReader.Str('password_salt');
    AUser.PasswordIterations := LReader.Int('password_iterations');
    AUser.IsActive := LReader.Bool('is_active');
    AUser.FailedAttempts := LReader.Int('failed_attempts');
    AUser.IsLocked := not LReader.IsNull('locked_until');
    if AUser.IsLocked then
      AUser.LockedUntil := LReader.Date('locked_until')
    else
      AUser.LockedUntil := 0;
  end;
end;

function TUserRepository.FindByUsername(const AUsername: string; out AUser: TUserRecord): Boolean;
begin
  Result := ReadWith(
    'SELECT id, username, full_name, password_hash, password_salt, password_iterations, is_active, failed_attempts, locked_until ' +
    'FROM users WHERE username = :username', P('username', AUsername), AUser);
end;

function TUserRepository.ReadUser(const AId: Int64; out AUser: TUserRecord): Boolean;
begin
  Result := ReadWith(
    'SELECT id, username, full_name, password_hash, password_salt, password_iterations, is_active, failed_attempts, locked_until ' +
    'FROM users WHERE id = :id', P('id', AId), AUser);
end;

function TUserRepository.Insert(const AUser: TUserRecord): Int64;
begin
  Result := FDb.NextId('seq_users');
  FDb.Execute(
    'INSERT INTO users (id, username, full_name, password_hash, password_salt, password_iterations, is_active) ' +
    'VALUES (:id, :username, :full_name, :hash, :salt, :iterations, :is_active)',
    [P('id', Result), P('username', AUser.Username), P('full_name', AUser.FullName), P('hash', AUser.PasswordHash),
     P('salt', AUser.PasswordSalt), P('iterations', Int64(AUser.PasswordIterations)), PBool('is_active', AUser.IsActive)]);
end;

procedure TUserRepository.AssignRole(const AUserId: Int64; const ARoleCode: string);
begin
  FDb.Execute('INSERT INTO user_roles (user_id, role_id) SELECT CAST(:user_id AS BIGINT), id FROM roles WHERE code = :code',
    [P('user_id', AUserId), P('code', ARoleCode)]);
end;

procedure TUserRepository.SavePassword(const AUserId: Int64; const AHash, ASalt: string; const AIterations: Integer);
begin
  FDb.Execute('UPDATE users SET password_hash = :hash, password_salt = :salt, password_iterations = :iterations WHERE id = :id',
    [P('hash', AHash), P('salt', ASalt), P('iterations', Int64(AIterations)), P('id', AUserId)]);
end;

procedure TUserRepository.RecordLoginFailure(const AUserId: Int64; const AFailedAttempts: Integer; const AHasLock: Boolean; const ALockedUntil: TDateTime);
var
  LLock: TDbParam;
begin
  if AHasLock then
    LLock := PDateTime('locked_until', ALockedUntil)
  else
    LLock := PNull('locked_until');
  FDb.Execute('UPDATE users SET failed_attempts = :failed, locked_until = :locked_until WHERE id = :id',
    [P('failed', Int64(AFailedAttempts)), LLock, P('id', AUserId)]);
end;

procedure TUserRepository.ClearLoginFailures(const AUserId: Int64);
begin
  FDb.Execute('UPDATE users SET failed_attempts = 0, locked_until = NULL WHERE id = :id', [P('id', AUserId)]);
end;

function TUserRepository.PermissionsOf(const AUserId: Int64): TTextArray;
var
  LReader: IDbReader;
  LCount: Integer;
begin
  LReader := FDb.Query(
    'SELECT DISTINCT rp.permission_code FROM role_permissions rp JOIN user_roles ur ON ur.role_id = rp.role_id WHERE ur.user_id = :id',
    [P('id', AUserId)]);
  LCount := 0;
  SetLength(Result, 0);
  while not LReader.Eof do
  begin
    SetLength(Result, LCount + 1);
    Result[LCount] := LReader.Str('permission_code');
    Inc(LCount);
    LReader.Next;
  end;
end;

{ TAuditLog }

constructor TAuditLog.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

procedure TAuditLog.Add(const AUserId: Int64; const AAction, AEntityType: string; const AEntityId: Int64; const ACorrelationId, ADetailsJson: string);
begin
  FDb.Execute(
    'INSERT INTO audit_events (id, user_id, action, entity_type, entity_id, correlation_id, details) ' +
    'VALUES (NEXT VALUE FOR seq_audit_events, :user_id, :action, :entity_type, :entity_id, :correlation_id, :details)',
    [PIdOrNull('user_id', AUserId), P('action', AAction), P('entity_type', AEntityType), P('entity_id', AEntityId),
     PTextOrNull('correlation_id', ACorrelationId), PTextOrNull('details', ADetailsJson)]);
end;

{ TOutboxRepository }

constructor TOutboxRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

procedure TOutboxRepository.Enqueue(const AEvent: TOutboxEvent);
begin
  FDb.Execute(
    'INSERT INTO outbox_events (id, event_type, aggregate_type, aggregate_id, payload, idempotency_key, correlation_id) ' +
    'VALUES (NEXT VALUE FOR seq_outbox_events, :event_type, :aggregate_type, :aggregate_id, :payload, :key_value, :correlation_id)',
    [P('event_type', AEvent.EventType), P('aggregate_type', AEvent.AggregateType), P('aggregate_id', AEvent.AggregateId),
     P('payload', AEvent.Payload), P('key_value', AEvent.IdempotencyKey), PTextOrNull('correlation_id', AEvent.CorrelationId)]);
end;

function TOutboxRepository.ClaimDue(const ALimit: Integer; const ANow, AClaimUntil: TDateTime): TOutboxEventArray;
var
  LReader: IDbReader;
  LCount, LIndex: Integer;
begin
  { WITH LOCK SKIP LOCKED existe a partir do Firebird 5: o evento em posse de outro worker
    é ignorado em vez de bloquear esta consulta. }
  LReader := FDb.Query(
    'SELECT FIRST ' + IntToStr(ALimit) + ' id, event_type, aggregate_type, aggregate_id, payload, idempotency_key, correlation_id, attempts ' +
    'FROM outbox_events WHERE status = ''PENDING'' AND next_attempt_at <= :now_value ' +
    'AND (claimed_until IS NULL OR claimed_until < :now_value) ORDER BY id WITH LOCK SKIP LOCKED',
    [PDateTime('now_value', ANow)]);
  LCount := 0;
  SetLength(Result, 0);
  while not LReader.Eof do
  begin
    SetLength(Result, LCount + 1);
    Result[LCount].Id := LReader.Int('id');
    Result[LCount].EventType := LReader.Str('event_type');
    Result[LCount].AggregateType := LReader.Str('aggregate_type');
    Result[LCount].AggregateId := LReader.Int('aggregate_id');
    Result[LCount].Payload := LReader.Str('payload');
    Result[LCount].IdempotencyKey := LReader.Str('idempotency_key');
    Result[LCount].CorrelationId := LReader.Str('correlation_id');
    Result[LCount].Attempts := LReader.Int('attempts') + 1;
    Inc(LCount);
    LReader.Next;
  end;
  LReader := nil;
  for LIndex := 0 to LCount - 1 do
    FDb.Execute('UPDATE outbox_events SET attempts = attempts + 1, claimed_until = :claim_until WHERE id = :id',
      [PDateTime('claim_until', AClaimUntil), P('id', Result[LIndex].Id)]);
end;

procedure TOutboxRepository.MarkSent(const AId: Int64; const ANow: TDateTime);
begin
  FDb.Execute('UPDATE outbox_events SET status = ''SENT'', sent_at = :now_value, claimed_until = NULL, last_error = NULL WHERE id = :id',
    [PDateTime('now_value', ANow), P('id', AId)]);
end;

procedure TOutboxRepository.MarkRetry(const AId: Int64; const ANextAttempt: TDateTime; const AError: string);
begin
  FDb.Execute('UPDATE outbox_events SET next_attempt_at = :next_attempt, claimed_until = NULL, last_error = :error WHERE id = :id',
    [PDateTime('next_attempt', ANextAttempt), P('error', Copy(AError, 1, 500)), P('id', AId)]);
end;

procedure TOutboxRepository.MarkDead(const AId: Int64; const AError: string);
begin
  FDb.Execute('UPDATE outbox_events SET status = ''DEAD'', claimed_until = NULL, last_error = :error WHERE id = :id',
    [P('error', Copy(AError, 1, 500)), P('id', AId)]);
end;

procedure TOutboxRepository.Requeue(const AId: Int64; const ANow: TDateTime);
begin
  FDb.Execute('UPDATE outbox_events SET status = ''PENDING'', attempts = 0, next_attempt_at = :now_value, claimed_until = NULL WHERE id = :id AND status = ''DEAD''',
    [PDateTime('now_value', ANow), P('id', AId)]);
end;

{ TIntegrationLogRepository }

constructor TIntegrationLogRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

procedure TIntegrationLogRepository.Add(const AEntry: TIntegrationLogEntry);
var
  LStatus: TDbParam;
begin
  if AEntry.HttpStatus > 0 then
    LStatus := P('http_status', Int64(AEntry.HttpStatus))
  else
    LStatus := PNull('http_status');
  FDb.Execute(
    'INSERT INTO integration_logs (id, correlation_id, idempotency_key, http_method, url, attempt, http_status, duration_ms, outcome, error_message, response_excerpt) ' +
    'VALUES (NEXT VALUE FOR seq_integration_logs, :correlation_id, :key_value, :method, :url, :attempt, :http_status, :duration_ms, :outcome, :error_message, :excerpt)',
    [PTextOrNull('correlation_id', AEntry.CorrelationId), PTextOrNull('key_value', AEntry.IdempotencyKey), P('method', AEntry.Method), P('url', AEntry.Url),
     P('attempt', Int64(AEntry.Attempt)), LStatus, P('duration_ms', Int64(AEntry.DurationMs)), P('outcome', AEntry.Outcome),
     PTextOrNull('error_message', Copy(AEntry.ErrorMessage, 1, 500)), PTextOrNull('excerpt', Copy(AEntry.ResponseExcerpt, 1, 500))]);
end;

{ TMetricsRepository }

constructor TMetricsRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

procedure TMetricsRepository.Add(const AMetric, ACorrelationId, ADetail: string; const ADurationMs: Int64);
begin
  FDb.Execute(
    'INSERT INTO metric_events (id, metric, correlation_id, detail, duration_ms) VALUES (NEXT VALUE FOR seq_metric_events, :metric, :correlation_id, :detail, :duration_ms)',
    [P('metric', AMetric), PTextOrNull('correlation_id', ACorrelationId), PTextOrNull('detail', Copy(ADetail, 1, 200)), P('duration_ms', ADurationMs)]);
end;

{ TSettingsRepository }

constructor TSettingsRepository.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
end;

function TSettingsRepository.GetText(const AKey, ADefault: string): string;
var
  LReader: IDbReader;
begin
  LReader := FDb.Query('SELECT setting_value FROM settings WHERE setting_key = :key_value', [P('key_value', AKey)]);
  if LReader.Eof then
    Result := ADefault
  else
    Result := LReader.Str('setting_value');
end;

procedure TSettingsRepository.SetText(const AKey, AValue: string);
begin
  FDb.Execute('UPDATE OR INSERT INTO settings (setting_key, setting_value) VALUES (:key_value, :value_text) MATCHING (setting_key)',
    [P('key_value', AKey), P('value_text', AValue)]);
end;

end.
