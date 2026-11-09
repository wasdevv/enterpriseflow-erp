unit EF.Tests.Faults;

{ Falha injetada num ponto exato do fluxo, no meio da transação, com o banco real. }

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Quantity, EF.Domain.Stock,
  EF.Application.Ports;

type
  EInjectedFault = class(Exception);

  TLockRecord = record
    ProductId, WarehouseId: Int64;
  end;

  { Delegação manual: AddMovement falha, se pedido, e LockBalance registra a ordem. }
  TFailingStockRepository = class(TInterfacedObject, IStockRepository)
  private
    FInner: IStockRepository;
    FFailOn: TMovementType;
    FFails: Boolean;
  public
    Locks: array of TLockRecord;
    constructor Create(const AInner: IStockRepository; const AFailOn: TMovementType);
    constructor CreateRecording(const AInner: IStockRepository);
    procedure EnsureBalance(const AProductId, AWarehouseId: Int64);
    function LockBalance(const AProductId, AWarehouseId: Int64; out ABalance: TStockBalance): Boolean;
    procedure SaveBalance(const AProductId, AWarehouseId: Int64; const ABalance: TStockBalance);
    procedure AddMovement(const AMovement: TMovementRecord);
    function DescribeKey(const AProductId, AWarehouseId: Int64): string;
    function AddReservation(const AReservation: TReservationRecord): Int64;
    function ReservationsOfOrder(const AOrderId: Int64): TReservationArray;
    function CloseReservation(const AReservationId: Int64; const AStatus: TReservationStatus): Boolean;
    function AddTransfer(const AProductId, AFrom, ATo: Int64; const AQuantity: TQuantity; const AReason: string; const AUserId: Int64): Int64;
    function AddAdjustment(const AProductId, AWarehouseId: Int64; const ACounted: TQuantity; const AReason: string; const AUserId: Int64): Int64;
    function LockAdjustment(const AId: Int64; out AAdjustment: TAdjustmentRecord): Boolean;
    procedure DecideAdjustment(const AId: Int64; const AStatus: string; const AUserId: Int64);
  end;

  TFailingUnitOfWork = class(TInterfacedObject, IUnitOfWork)
  private
    FInner: IUnitOfWork;
    FStock: IStockRepository;
  public
    constructor Create(const AInner: IUnitOfWork; const AFailOn: TMovementType);
    constructor CreateWith(const AInner: IUnitOfWork; const AStock: IStockRepository);
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

implementation

constructor TFailingStockRepository.Create(const AInner: IStockRepository; const AFailOn: TMovementType);
begin
  inherited Create;
  FInner := AInner;
  FFailOn := AFailOn;
  FFails := True;
end;

constructor TFailingStockRepository.CreateRecording(const AInner: IStockRepository);
begin
  inherited Create;
  FInner := AInner;
  FFails := False;
end;

procedure TFailingStockRepository.AddMovement(const AMovement: TMovementRecord);
begin
  if FFails and (AMovement.MovementType = FFailOn) then
    raise EInjectedFault.Create('Falha injetada ao gravar movimento');
  FInner.AddMovement(AMovement);
end;

procedure TFailingStockRepository.EnsureBalance(const AProductId, AWarehouseId: Int64);
begin
  FInner.EnsureBalance(AProductId, AWarehouseId);
end;

function TFailingStockRepository.LockBalance(const AProductId, AWarehouseId: Int64; out ABalance: TStockBalance): Boolean;
begin
  SetLength(Locks, Length(Locks) + 1);
  Locks[High(Locks)].ProductId := AProductId;
  Locks[High(Locks)].WarehouseId := AWarehouseId;
  Result := FInner.LockBalance(AProductId, AWarehouseId, ABalance);
end;

procedure TFailingStockRepository.SaveBalance(const AProductId, AWarehouseId: Int64; const ABalance: TStockBalance);
begin
  FInner.SaveBalance(AProductId, AWarehouseId, ABalance);
end;

function TFailingStockRepository.DescribeKey(const AProductId, AWarehouseId: Int64): string;
begin
  Result := FInner.DescribeKey(AProductId, AWarehouseId);
end;

function TFailingStockRepository.AddReservation(const AReservation: TReservationRecord): Int64;
begin
  Result := FInner.AddReservation(AReservation);
end;

function TFailingStockRepository.ReservationsOfOrder(const AOrderId: Int64): TReservationArray;
begin
  Result := FInner.ReservationsOfOrder(AOrderId);
end;

function TFailingStockRepository.CloseReservation(const AReservationId: Int64; const AStatus: TReservationStatus): Boolean;
begin
  Result := FInner.CloseReservation(AReservationId, AStatus);
end;

function TFailingStockRepository.AddTransfer(const AProductId, AFrom, ATo: Int64; const AQuantity: TQuantity; const AReason: string; const AUserId: Int64): Int64;
begin
  Result := FInner.AddTransfer(AProductId, AFrom, ATo, AQuantity, AReason, AUserId);
end;

function TFailingStockRepository.AddAdjustment(const AProductId, AWarehouseId: Int64; const ACounted: TQuantity; const AReason: string; const AUserId: Int64): Int64;
begin
  Result := FInner.AddAdjustment(AProductId, AWarehouseId, ACounted, AReason, AUserId);
end;

function TFailingStockRepository.LockAdjustment(const AId: Int64; out AAdjustment: TAdjustmentRecord): Boolean;
begin
  Result := FInner.LockAdjustment(AId, AAdjustment);
end;

procedure TFailingStockRepository.DecideAdjustment(const AId: Int64; const AStatus: string; const AUserId: Int64);
begin
  FInner.DecideAdjustment(AId, AStatus, AUserId);
end;

constructor TFailingUnitOfWork.Create(const AInner: IUnitOfWork; const AFailOn: TMovementType);
begin
  inherited Create;
  FInner := AInner;
  FStock := TFailingStockRepository.Create(AInner.Stock, AFailOn);
end;

constructor TFailingUnitOfWork.CreateWith(const AInner: IUnitOfWork; const AStock: IStockRepository);
begin
  inherited Create;
  FInner := AInner;
  FStock := AStock;
end;

procedure TFailingUnitOfWork.StartTransaction;
begin
  FInner.StartTransaction;
end;

procedure TFailingUnitOfWork.Commit;
begin
  FInner.Commit;
end;

procedure TFailingUnitOfWork.Rollback;
begin
  FInner.Rollback;
end;

function TFailingUnitOfWork.InTransaction: Boolean;
begin
  Result := FInner.InTransaction;
end;

function TFailingUnitOfWork.Stock: IStockRepository;
begin
  Result := FStock;
end;

function TFailingUnitOfWork.Orders: IOrderRepository;
begin
  Result := FInner.Orders;
end;

function TFailingUnitOfWork.Purchases: IPurchaseRepository;
begin
  Result := FInner.Purchases;
end;

function TFailingUnitOfWork.Receivables: IReceivableRepository;
begin
  Result := FInner.Receivables;
end;

function TFailingUnitOfWork.Catalog: ICatalogRepository;
begin
  Result := FInner.Catalog;
end;

function TFailingUnitOfWork.Users: IUserRepository;
begin
  Result := FInner.Users;
end;

function TFailingUnitOfWork.Audit: IAuditLog;
begin
  Result := FInner.Audit;
end;

function TFailingUnitOfWork.Outbox: IOutboxRepository;
begin
  Result := FInner.Outbox;
end;

function TFailingUnitOfWork.IntegrationLogs: IIntegrationLogRepository;
begin
  Result := FInner.IntegrationLogs;
end;

function TFailingUnitOfWork.Metrics: IMetricsRepository;
begin
  Result := FInner.Metrics;
end;

function TFailingUnitOfWork.Settings: ISettingsRepository;
begin
  Result := FInner.Settings;
end;

end.
