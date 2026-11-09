unit EF.Application.Catalog;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Application.Ports, EF.Application.Base;

type
  TCatalogService = class(TServiceBase)
  public
    function SaveProduct(const AProduct: TProductRecord): Int64;
    function SaveCustomer(const ACustomer: TCustomerRecord): Int64;
    function SaveParty(const AParty: TPartyRecord): Int64;
    function SaveWarehouse(const AWarehouse: TWarehouseRecord): Int64;
    function AddLocation(const AWarehouseId: Int64; const ACode, ADescription: string): Int64;
    function AddCategory(const AName: string): Int64;
  end;

  TAuthService = class
  private
    FUow: IUnitOfWork;
    FClock: IClock;
  public
    constructor Create(const AUow: IUnitOfWork; const AClock: IClock);
    { Mensagem única para usuário inexistente e senha errada: não revela quem existe. }
    function Login(const AUsername, APassword: string): TUserContext;
    procedure ChangePassword(const AContext: TUserContext; const ACurrent, ANew: string);
    function CreateUser(const AContext: TUserContext; const AUsername, AFullName, APassword: string; const ARoles: array of string): Int64;
  end;

const
  CMaxLoginAttempts = 5;
  CLockMinutes = 15;
  CMinPasswordLength = 8;

implementation

uses
  EF.Domain.Exceptions,
  EF.Shared.Crypto, EF.Shared.Documents, EF.Shared.Text;

function TCatalogService.SaveProduct(const AProduct: TProductRecord): Int64;
var
  LBefore: TProductRecord;
  LChanges: TJsonObjectBuilder;
  LChanged: Boolean;
begin
  BeginOperation(PermCatalogManage);
  if Trim(AProduct.Sku) = '' then
    raise EValidationError.Create('Informe o SKU.');
  if Trim(AProduct.Name) = '' then
    raise EValidationError.Create('Informe o nome do produto.');
  if AProduct.SalePrice.IsNegative then
    raise EValidationError.Create('O preço não pode ser negativo.');
  if AProduct.MinimumStock.IsNegative then
    raise EValidationError.Create('O estoque mínimo não pode ser negativo.');
  FUow.StartTransaction;
  try
    LChanges := TJsonObjectBuilder.New;
    LChanged := False;
    if AProduct.Id <> 0 then
    begin
      if not FUow.Catalog.ReadProduct(AProduct.Id, LBefore) then
        raise ENotFound.CreateFmt('Produto %d não encontrado.', [AProduct.Id]);
      if LBefore.SalePrice <> AProduct.SalePrice then
      begin
        LChanges := LChanges.Str('sale_price_from', LBefore.SalePrice.ToInvariant).Str('sale_price_to', AProduct.SalePrice.ToInvariant);
        LChanged := True;
      end;
      if LBefore.Name <> AProduct.Name then
      begin
        LChanges := LChanges.Str('name_from', LBefore.Name).Str('name_to', AProduct.Name);
        LChanged := True;
      end;
      if LBefore.IsActive <> AProduct.IsActive then
      begin
        LChanges := LChanges.Str('active_to', BoolToStr(AProduct.IsActive, True));
        LChanged := True;
      end;
    end;
    Result := FUow.Catalog.SaveProduct(AProduct);
    if AProduct.Id = 0 then
      Audit('product.created', 'product', Result, TJsonObjectBuilder.New.Str('sku', AProduct.Sku).ToJson)
    else if LChanged then
      Audit('product.updated', 'product', Result, LChanges.ToJson);
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      raise EValidationError.CreateFmt('Já existe produto com o SKU %s.', [AProduct.Sku]);
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

function TCatalogService.SaveCustomer(const ACustomer: TCustomerRecord): Int64;
var
  LBefore, LRecord: TCustomerRecord;
begin
  BeginOperation(PermCatalogManage);
  LRecord := ACustomer;
  LRecord.Document := OnlyDigits(ACustomer.Document);
  if Trim(LRecord.Name) = '' then
    raise EValidationError.Create('Informe o nome do cliente.');
  if not IsValidDocument(LRecord.Document) then
    raise EValidationError.Create('CPF ou CNPJ inválido.');
  if (Trim(LRecord.Email) <> '') and not IsValidEmail(LRecord.Email) then
    raise EValidationError.Create('E-mail inválido.');
  if LRecord.CreditLimit.IsNegative then
    raise EValidationError.Create('O limite de crédito não pode ser negativo.');
  FUow.StartTransaction;
  try
    if ACustomer.Id <> 0 then
    begin
      if not FUow.Catalog.ReadCustomer(ACustomer.Id, LBefore) then
        raise ENotFound.CreateFmt('Cliente %d não encontrado.', [ACustomer.Id]);
      if LBefore.CreditLimit <> LRecord.CreditLimit then
        Audit('customer.credit_limit_changed', 'customer', ACustomer.Id, TJsonObjectBuilder.New
          .Str('from', LBefore.CreditLimit.ToInvariant).Str('to', LRecord.CreditLimit.ToInvariant).ToJson);
    end;
    Result := FUow.Catalog.SaveCustomer(LRecord);
    if ACustomer.Id = 0 then
      Audit('customer.created', 'customer', Result);
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      raise EValidationError.Create('Já existe cliente com este CPF/CNPJ.');
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

function TCatalogService.SaveParty(const AParty: TPartyRecord): Int64;
var
  LRecord: TPartyRecord;
begin
  BeginOperation(PermCatalogManage);
  LRecord := AParty;
  LRecord.Document := OnlyDigits(AParty.Document);
  if Trim(LRecord.Name) = '' then
    raise EValidationError.Create('Informe o nome.');
  if not IsValidCnpj(LRecord.Document) then
    raise EValidationError.Create('CNPJ inválido.');
  FUow.StartTransaction;
  try
    Result := FUow.Catalog.SaveParty(LRecord);
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      raise EValidationError.Create('Já existe cadastro com este CNPJ.');
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

function TCatalogService.SaveWarehouse(const AWarehouse: TWarehouseRecord): Int64;
begin
  BeginOperation(PermCatalogManage);
  if (Trim(AWarehouse.Code) = '') or (Trim(AWarehouse.Name) = '') then
    raise EValidationError.Create('Informe código e nome do depósito.');
  FUow.StartTransaction;
  try
    Result := FUow.Catalog.SaveWarehouse(AWarehouse);
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      raise EValidationError.CreateFmt('Já existe depósito com o código %s.', [AWarehouse.Code]);
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

function TCatalogService.AddLocation(const AWarehouseId: Int64; const ACode, ADescription: string): Int64;
begin
  BeginOperation(PermCatalogManage);
  if Trim(ACode) = '' then
    raise EValidationError.Create('Informe o código do endereço.');
  FUow.StartTransaction;
  try
    Result := FUow.Catalog.AddLocation(AWarehouseId, ACode, ADescription);
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      raise EValidationError.CreateFmt('O endereço %s já existe neste depósito.', [ACode]);
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

function TCatalogService.AddCategory(const AName: string): Int64;
begin
  BeginOperation(PermCatalogManage);
  if Trim(AName) = '' then
    raise EValidationError.Create('Informe o nome da categoria.');
  FUow.StartTransaction;
  try
    Result := FUow.Catalog.AddCategory(AName);
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      raise EValidationError.CreateFmt('A categoria %s já existe.', [AName]);
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

constructor TAuthService.Create(const AUow: IUnitOfWork; const AClock: IClock);
begin
  inherited Create;
  FUow := AUow;
  FClock := AClock;
end;

function TAuthService.Login(const AUsername, APassword: string): TUserContext;
const
  CInvalid = 'Usuário ou senha inválidos.';
var
  LUser: TUserRecord;
  LAttempts: Integer;
  LLock: Boolean;
begin
  FUow.StartTransaction;
  try
    if not FUow.Users.FindByUsername(AUsername, LUser) then
    begin
      { Mesmo custo de uma senha errada: o tempo de resposta não revela se o usuário existe. }
      HashPassword(APassword, 'nao-existe', CPasswordIterations);
      raise EAuthenticationFailed.Create(CInvalid);
    end;
    if not LUser.IsActive then
      raise EAuthenticationFailed.Create(CInvalid);
    if LUser.IsLocked and (LUser.LockedUntil > FClock.Now) then
      raise EAuthenticationFailed.CreateFmt('Usuário bloqueado até %s por excesso de tentativas.', [FormatDateTime('hh":"nn', LUser.LockedUntil)]);

    if not ConstantTimeEquals(LUser.PasswordHash, HashPassword(APassword, LUser.PasswordSalt, LUser.PasswordIterations)) then
    begin
      LAttempts := LUser.FailedAttempts + 1;
      LLock := LAttempts >= CMaxLoginAttempts;
      if LLock then
      begin
        FUow.Users.RecordLoginFailure(LUser.Id, 0, True, FClock.Now + CLockMinutes / (24 * 60));
        FUow.Audit.Add(LUser.Id, 'user.locked', 'user', LUser.Id, '', '');
      end
      else
        FUow.Users.RecordLoginFailure(LUser.Id, LAttempts, False, 0);
      FUow.Commit;
      raise EAuthenticationFailed.Create(CInvalid);
    end;

    FUow.Users.ClearLoginFailures(LUser.Id);
    Result.UserId := LUser.Id;
    Result.Username := LUser.Username;
    Result.Permissions := FUow.Users.PermissionsOf(LUser.Id);
    Result.CorrelationId := NewCorrelationId;
    FUow.Audit.Add(LUser.Id, 'user.login', 'user', LUser.Id, Result.CorrelationId, '');
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

procedure TAuthService.ChangePassword(const AContext: TUserContext; const ACurrent, ANew: string);
var
  LUser: TUserRecord;
  LSalt: string;
begin
  if Length(ANew) < CMinPasswordLength then
    raise EValidationError.CreateFmt('A nova senha precisa de ao menos %d caracteres.', [CMinPasswordLength]);
  FUow.StartTransaction;
  try
    if not FUow.Users.ReadUser(AContext.UserId, LUser) then
      raise ENotFound.Create('Usuário não encontrado.');
    if not ConstantTimeEquals(LUser.PasswordHash, HashPassword(ACurrent, LUser.PasswordSalt, LUser.PasswordIterations)) then
      raise EAuthenticationFailed.Create('Senha atual incorreta.');
    LSalt := NewSaltHex;
    FUow.Users.SavePassword(LUser.Id, HashPassword(ANew, LSalt, CPasswordIterations), LSalt, CPasswordIterations);
    FUow.Audit.Add(LUser.Id, 'user.password_changed', 'user', LUser.Id, AContext.CorrelationId, '');
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

function TAuthService.CreateUser(const AContext: TUserContext; const AUsername, AFullName, APassword: string; const ARoles: array of string): Int64;
var
  LUser: TUserRecord;
  LIndex: Integer;
begin
  if not AContext.Has(PermUsersManage) then
    raise EPermissionDenied.Create('Sem permissão para gerenciar usuários.');
  if (Trim(AUsername) = '') or (Trim(AFullName) = '') then
    raise EValidationError.Create('Informe usuário e nome.');
  if Length(APassword) < CMinPasswordLength then
    raise EValidationError.CreateFmt('A senha precisa de ao menos %d caracteres.', [CMinPasswordLength]);
  LUser.Id := 0;
  LUser.Username := AUsername;
  LUser.FullName := AFullName;
  LUser.PasswordSalt := NewSaltHex;
  LUser.PasswordHash := HashPassword(APassword, LUser.PasswordSalt, CPasswordIterations);
  LUser.PasswordIterations := CPasswordIterations;
  LUser.FailedAttempts := 0;
  LUser.IsActive := True;
  LUser.IsLocked := False;
  LUser.LockedUntil := 0;
  FUow.StartTransaction;
  try
    Result := FUow.Users.Insert(LUser);
    for LIndex := Low(ARoles) to High(ARoles) do
      FUow.Users.AssignRole(Result, ARoles[LIndex]);
    FUow.Audit.Add(AContext.UserId, 'user.created', 'user', Result, AContext.CorrelationId, '');
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      raise EValidationError.CreateFmt('O usuário %s já existe.', [AUsername]);
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

end.
