unit EF.Infrastructure.UnitOfWork;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Application.Ports, EF.Infrastructure.Database;

type
  TUnitOfWork = class(TInterfacedObject, IUnitOfWork)
  private
    FDb: IDbSession;
    FStock: IStockRepository;
    FOrders: IOrderRepository;
    FPurchases: IPurchaseRepository;
    FReceivables: IReceivableRepository;
    FCatalog: ICatalogRepository;
    FUsers: IUserRepository;
    FAudit: IAuditLog;
    FOutbox: IOutboxRepository;
    FIntegrationLogs: IIntegrationLogRepository;
    FMetrics: IMetricsRepository;
    FSettings: ISettingsRepository;
  public
    constructor Create(const ADb: IDbSession);
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    function Stock: IStockRepository;
    function Orders: IOrderRepository;
    function Purchases: IPurchaseRepository;
    function Receivables: IReceivableRepository;
    function Catalog: ICatalogRepository;
    function Users: IUserRepository;
    function Audit: IAuditLog;
    function Outbox: IOutboxRepository;
    function IntegrationLogs: IIntegrationLogRepository;
    function Metrics: IMetricsRepository;
    function Settings: ISettingsRepository;
  end;

  TSystemClock = class(TInterfacedObject, IClock)
  public
    function Now: TDateTime;
    function Today: TDateTime;
  end;

implementation

uses
  EF.Infrastructure.Repositories.Stock,
  EF.Infrastructure.Repositories.Sales,
  EF.Infrastructure.Repositories.Support;

constructor TUnitOfWork.Create(const ADb: IDbSession);
begin
  inherited Create;
  FDb := ADb;
  FStock := TStockRepository.Create(ADb);
  FOrders := TOrderRepository.Create(ADb);
  FPurchases := TPurchaseRepository.Create(ADb);
  FReceivables := TReceivableRepository.Create(ADb);
  FCatalog := TCatalogRepository.Create(ADb);
  FUsers := TUserRepository.Create(ADb);
  FAudit := TAuditLog.Create(ADb);
  FOutbox := TOutboxRepository.Create(ADb);
  FIntegrationLogs := TIntegrationLogRepository.Create(ADb);
  FMetrics := TMetricsRepository.Create(ADb);
  FSettings := TSettingsRepository.Create(ADb);
end;

procedure TUnitOfWork.StartTransaction;
begin
  FDb.StartTransaction;
end;

procedure TUnitOfWork.Commit;
begin
  FDb.Commit;
end;

procedure TUnitOfWork.Rollback;
begin
  FDb.Rollback;
end;

function TUnitOfWork.InTransaction: Boolean;
begin
  Result := FDb.InTransaction;
end;

function TUnitOfWork.Stock: IStockRepository;
begin
  Result := FStock;
end;

function TUnitOfWork.Orders: IOrderRepository;
begin
  Result := FOrders;
end;

function TUnitOfWork.Purchases: IPurchaseRepository;
begin
  Result := FPurchases;
end;

function TUnitOfWork.Receivables: IReceivableRepository;
begin
  Result := FReceivables;
end;

function TUnitOfWork.Catalog: ICatalogRepository;
begin
  Result := FCatalog;
end;

function TUnitOfWork.Users: IUserRepository;
begin
  Result := FUsers;
end;

function TUnitOfWork.Audit: IAuditLog;
begin
  Result := FAudit;
end;

function TUnitOfWork.Outbox: IOutboxRepository;
begin
  Result := FOutbox;
end;

function TUnitOfWork.IntegrationLogs: IIntegrationLogRepository;
begin
  Result := FIntegrationLogs;
end;

function TUnitOfWork.Metrics: IMetricsRepository;
begin
  Result := FMetrics;
end;

function TUnitOfWork.Settings: ISettingsRepository;
begin
  Result := FSettings;
end;

function TSystemClock.Now: TDateTime;
begin
  Result := SysUtils.Now;
end;

function TSystemClock.Today: TDateTime;
begin
  Result := SysUtils.Date;
end;

end.
