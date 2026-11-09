unit EF.Application.Ports;

{ Contratos que a aplicação exige da infraestrutura. Nada aqui conhece SQL nem FireDAC. }

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Money, EF.Domain.Quantity, EF.Domain.Stock, EF.Domain.OrderState,
  EF.Domain.Receivables;

const
  PermCatalogManage = 'catalog.manage';
  PermUsersManage = 'users.manage';
  PermStockMove = 'stock.move';
  PermStockAdjustRequest = 'stock.adjust.request';
  PermStockAdjustApprove = 'stock.adjust.approve';
  PermPurchaseManage = 'purchase.manage';
  PermOrderCreate = 'order.create';
  PermOrderConfirm = 'order.confirm';
  PermOrderCancel = 'order.cancel';
  PermOrderFulfill = 'order.fulfill';
  PermInvoiceCreate = 'invoice.create';
  PermReceivableSettle = 'receivable.settle';
  PermReceivableReverse = 'receivable.reverse';
  PermReportsView = 'reports.view';
  PermIntegrationManage = 'integration.manage';

type
  TTextArray = array of string;
  TTextMatrix = array of TTextArray;

  { Resultado tabular para grades e CSV. A coluna ID, quando existe, fica oculta na tela. }
  TDataTable = record
    Columns: TTextArray;
    Rows: TTextMatrix;
    function ColumnIndex(const AName: string): Integer;
    function Cell(const ARow: Integer; const AColumn: string): string;
  end;

  TUserContext = record
    UserId: Int64;
    Username: string;
    Permissions: TTextArray;
    CorrelationId: string;
    function Has(const APermission: string): Boolean;
  end;

  IClock = interface
    function Now: TDateTime;
    function Today: TDateTime;
  end;

  { Estoque }
  TMovementRecord = record
    ProductId, WarehouseId: Int64;
    MovementType: TMovementType;
    Quantity, OnHandDelta, ReservedDelta, OnHandAfter, ReservedAfter: TQuantity;
    Reason: string;
    UserId: Int64;
    SourceType: string;
    SourceId: Int64;
    CorrelationId: string;
  end;

  TReservationRecord = record
    Id, OrderId, ItemId, ProductId, WarehouseId: Int64;
    Quantity: TQuantity;
    Status: TReservationStatus;
  end;
  TReservationArray = array of TReservationRecord;

  TAdjustmentRecord = record
    Id, ProductId, WarehouseId, RequestedBy: Int64;
    Counted: TQuantity;
    Reason, Status: string;
  end;

  IStockRepository = interface
    procedure EnsureBalance(const AProductId, AWarehouseId: Int64);
    function LockBalance(const AProductId, AWarehouseId: Int64; out ABalance: TStockBalance): Boolean;
    procedure SaveBalance(const AProductId, AWarehouseId: Int64; const ABalance: TStockBalance);
    procedure AddMovement(const AMovement: TMovementRecord);
    function DescribeKey(const AProductId, AWarehouseId: Int64): string;
    function AddReservation(const AReservation: TReservationRecord): Int64;
    function ReservationsOfOrder(const AOrderId: Int64): TReservationArray;
    { Só fecha reserva ACTIVE. False = já encerrada: é o "exatamente uma vez" da liberação. }
    function CloseReservation(const AReservationId: Int64; const AStatus: TReservationStatus): Boolean;
    function AddTransfer(const AProductId, AFrom, ATo: Int64; const AQuantity: TQuantity; const AReason: string; const AUserId: Int64): Int64;
    function AddAdjustment(const AProductId, AWarehouseId: Int64; const ACounted: TQuantity; const AReason: string; const AUserId: Int64): Int64;
    function LockAdjustment(const AId: Int64; out AAdjustment: TAdjustmentRecord): Boolean;
    procedure DecideAdjustment(const AId: Int64; const AStatus: string; const AUserId: Int64);
  end;

  { Vendas }
  TOrderHeader = record
    Id, CustomerId, SellerId, CarrierId: Int64;
    Status: TOrderStatus;
    IdempotencyKey: string;
    Total: TMoney;
    Installments, IntervalDays: Integer;
  end;

  TOrderItem = record
    Id, OrderId, ProductId, WarehouseId: Int64;
    Quantity: TQuantity;
    UnitPrice, LineTotal: TMoney;
  end;
  TOrderItemArray = array of TOrderItem;

  IOrderRepository = interface
    function FindByIdempotencyKey(const AKey: string; out AOrderId: Int64): Boolean;
    function Insert(const AHeader: TOrderHeader): Int64;
    function InsertItem(const AItem: TOrderItem): Int64;
    function Read(const AOrderId: Int64; out AHeader: TOrderHeader): Boolean;
    function Lock(const AOrderId: Int64; out AHeader: TOrderHeader): Boolean;
    function Items(const AOrderId: Int64): TOrderItemArray;
    procedure UpdateStatus(const AOrderId: Int64; const AStatus: TOrderStatus; const ACancelReason: string; const ACarrierId: Int64);
    procedure SetIdempotencyKey(const AOrderId: Int64; const AKey: string);
    procedure AddHistory(const AOrderId: Int64; const AHasFrom: Boolean; const AFrom, ATo: TOrderStatus; const AUserId: Int64; const AReason: string);
    { Soma de pedidos que já seguram estoque e ainda não viraram título. }
    function ReservedTotal(const ACustomerId, AExcludingOrderId: Int64): TMoney;
  end;

  { Compras }
  TPurchaseHeader = record
    Id, SupplierId, WarehouseId: Int64;
    Status: string;
  end;

  TPurchaseItem = record
    Id, ProductId: Int64;
    Ordered, Received: TQuantity;
    UnitCost: TMoney;
  end;
  TPurchaseItemArray = array of TPurchaseItem;

  IPurchaseRepository = interface
    function Insert(const ASupplierId, AWarehouseId: Int64; const ANote: string; const AUserId: Int64): Int64;
    function InsertItem(const AOrderId, AProductId: Int64; const AOrdered: TQuantity; const AUnitCost: TMoney): Int64;
    function Lock(const AOrderId: Int64; out AHeader: TPurchaseHeader): Boolean;
    function Items(const AOrderId: Int64): TPurchaseItemArray;
    procedure UpdateItemReceived(const AItemId: Int64; const AReceived: TQuantity);
    procedure UpdateStatus(const AOrderId: Int64; const AStatus: string);
    function FindReceiptByKey(const AKey: string; out AReceiptId: Int64): Boolean;
    function InsertReceipt(const AOrderId: Int64; const AKey, ANote: string; const AUserId: Int64): Int64;
    procedure InsertReceiptItem(const AReceiptId, AItemId: Int64; const AReceived, AOutstandingBefore, ADivergence: TQuantity; const ANote: string);
  end;

  { Financeiro }
  TInstallmentRecord = record
    Id, TitleId: Int64;
    Number: Integer;
    DueDate: TDateTime;
    State: TInstallmentState;
  end;

  TSettlementRecord = record
    Id, InstallmentId, ReversalOfId, UserId: Int64;
    Principal, Interest, Penalty, Discount: TMoney;
    PaidOn: TDateTime;
    IdempotencyKey, Note: string;
  end;

  IReceivableRepository = interface
    function NextInvoiceNumber: Int64;
    function InsertInvoice(const ANumber, AOrderId, ACustomerId: Int64; const ATotal: TMoney; const AUserId: Int64): Int64;
    function FindInvoiceOfOrder(const AOrderId: Int64; out AInvoiceId, ANumber: Int64): Boolean;
    function InsertTitle(const AInvoiceId, ACustomerId: Int64; const ATotal: TMoney): Int64;
    procedure InsertInstallment(const ATitleId: Int64; const APlanned: TPlannedInstallment);
    function ReadInstallment(const AId: Int64; out AInstallment: TInstallmentRecord): Boolean;
    function LockInstallment(const AId: Int64; out AInstallment: TInstallmentRecord): Boolean;
    procedure SaveInstallment(const AInstallment: TInstallmentRecord);
    function LockTitle(const ATitleId: Int64; out ATotal: TMoney): Boolean;
    function TitleSettled(const ATitleId: Int64): TMoney;
    procedure UpdateTitleStatus(const ATitleId: Int64; const AStatus: TTitleStatus);
    function FindSettlementByKey(const AKey: string; out ASettlementId: Int64): Boolean;
    function InsertSettlement(const ASettlement: TSettlementRecord): Int64;
    function ReadSettlement(const AId: Int64; out ASettlement: TSettlementRecord): Boolean;
    function HasReversal(const ASettlementId: Int64): Boolean;
    function OpenBalance(const ACustomerId: Int64): TMoney;
  end;

  { Cadastros }
  TProductRecord = record
    Id, CategoryId: Int64;
    Sku, Name, UnitCode: string;
    SalePrice: TMoney;
    MinimumStock: TQuantity;
    IsActive, AllowsFraction: Boolean;
  end;

  TCustomerRecord = record
    Id: Int64;
    Name, Document, Email, Phone: string;
    CreditLimit: TMoney;
    IsActive: Boolean;
  end;

  TPartyKind = (pkSupplier, pkCarrier);

  TPartyRecord = record
    Id: Int64;
    Kind: TPartyKind;
    Name, Document, Email, Phone: string;
    IsActive: Boolean;
  end;

  TWarehouseRecord = record
    Id: Int64;
    Code, Name: string;
    IsActive: Boolean;
  end;

  ICatalogRepository = interface
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

  { Usuários }
  TUserRecord = record
    Id: Int64;
    Username, FullName, PasswordHash, PasswordSalt: string;
    PasswordIterations, FailedAttempts: Integer;
    IsActive, IsLocked: Boolean;
    LockedUntil: TDateTime;
  end;

  IUserRepository = interface
    function FindByUsername(const AUsername: string; out AUser: TUserRecord): Boolean;
    function ReadUser(const AId: Int64; out AUser: TUserRecord): Boolean;
    function Insert(const AUser: TUserRecord): Int64;
    procedure AssignRole(const AUserId: Int64; const ARoleCode: string);
    procedure SavePassword(const AUserId: Int64; const AHash, ASalt: string; const AIterations: Integer);
    procedure RecordLoginFailure(const AUserId: Int64; const AFailedAttempts: Integer; const AHasLock: Boolean; const ALockedUntil: TDateTime);
    procedure ClearLoginFailures(const AUserId: Int64);
    function PermissionsOf(const AUserId: Int64): TTextArray;
  end;

  IAuditLog = interface
    procedure Add(const AUserId: Int64; const AAction, AEntityType: string; const AEntityId: Int64; const ACorrelationId, ADetailsJson: string);
  end;

  { Outbox e integração }
  TOutboxEvent = record
    Id, AggregateId: Int64;
    EventType, AggregateType, Payload, IdempotencyKey, CorrelationId: string;
    Attempts: Integer;
  end;
  TOutboxEventArray = array of TOutboxEvent;

  IOutboxRepository = interface
    procedure Enqueue(const AEvent: TOutboxEvent);
    { Bloqueia com SKIP LOCKED e marca a posse: dois workers nunca pegam o mesmo evento. }
    function ClaimDue(const ALimit: Integer; const ANow, AClaimUntil: TDateTime): TOutboxEventArray;
    procedure MarkSent(const AId: Int64; const ANow: TDateTime);
    procedure MarkRetry(const AId: Int64; const ANextAttempt: TDateTime; const AError: string);
    procedure MarkDead(const AId: Int64; const AError: string);
    procedure Requeue(const AId: Int64; const ANow: TDateTime);
  end;

  TIntegrationLogEntry = record
    CorrelationId, IdempotencyKey, Method, Url, Outcome, ErrorMessage, ResponseExcerpt: string;
    Attempt, HttpStatus, DurationMs: Integer;
  end;

  IIntegrationLogRepository = interface
    procedure Add(const AEntry: TIntegrationLogEntry);
  end;

  IMetricsRepository = interface
    procedure Add(const AMetric, ACorrelationId, ADetail: string; const ADurationMs: Int64);
  end;

  ISettingsRepository = interface
    function GetText(const AKey, ADefault: string): string;
    procedure SetText(const AKey, AValue: string);
  end;

  IUnitOfWork = interface
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

  TPublishOutcome = (poDelivered, poTransientFailure, poPermanentFailure);

  TPublishResult = record
    Outcome: TPublishOutcome;
    Detail: string;
  end;

  { Entrega um evento ao serviço externo. Chamado sem transação SQL aberta. }
  IEventPublisher = interface
    function Publish(const AEvent: TOutboxEvent): TPublishResult;
  end;

  IReadModel = interface
    function Products(const ASearch: string): TDataTable;
    function Customers(const ASearch: string): TDataTable;
    function Parties(const AKind: TPartyKind): TDataTable;
    function Warehouses: TDataTable;
    function Locations(const AWarehouseId: Int64): TDataTable;
    function Categories: TDataTable;
    function Units: TDataTable;
    function Users: TDataTable;
    function Roles: TDataTable;
    function StockBalances(const ASearch: string): TDataTable;
    function LowStock: TDataTable;
    function Kardex(const AProductId, AWarehouseId: Int64): TDataTable;
    function StockReconciliation: TDataTable;
    function PendingAdjustments: TDataTable;
    function SalesOrders(const AStatus: string): TDataTable;
    function SalesOrderItems(const AOrderId: Int64): TDataTable;
    function SalesOrderHistory(const AOrderId: Int64): TDataTable;
    function PurchaseOrders: TDataTable;
    function PurchaseOrderItems(const AOrderId: Int64): TDataTable;
    function PurchaseDivergences: TDataTable;
    function OpenInstallments(const AToday: TDateTime; const AOnlyOverdue: Boolean): TDataTable;
    function Settlements(const AInstallmentId: Int64): TDataTable;
    function CashFlow(const AFrom, ATo: TDateTime): TDataTable;
    function OutboxQueue: TDataTable;
    function IntegrationLog: TDataTable;
    function AuditTrail(const AEntityType: string; const AEntityId: Int64): TDataTable;
    function MetricsSummary: TDataTable;
  end;

implementation

function TDataTable.ColumnIndex(const AName: string): Integer;
var
  LIndex: Integer;
begin
  for LIndex := 0 to High(Columns) do
    if SameText(Columns[LIndex], AName) then
      Exit(LIndex);
  Result := -1;
end;

function TDataTable.Cell(const ARow: Integer; const AColumn: string): string;
var
  LColumn: Integer;
begin
  LColumn := ColumnIndex(AColumn);
  if LColumn < 0 then
    raise Exception.CreateFmt('Coluna inexistente: %s', [AColumn]);
  Result := Rows[ARow][LColumn];
end;

function TUserContext.Has(const APermission: string): Boolean;
var
  LIndex: Integer;
begin
  for LIndex := 0 to High(Permissions) do
    if Permissions[LIndex] = APermission then
      Exit(True);
  Result := False;
end;

end.
