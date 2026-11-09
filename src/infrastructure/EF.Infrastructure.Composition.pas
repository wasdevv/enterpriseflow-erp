unit EF.Infrastructure.Composition;

{ Monta os serviços. É o único lugar que conhece todas as camadas. }

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Application.Ports, EF.Application.Sales, EF.Application.Finance,
  EF.Application.Inventory, EF.Application.Catalog, EF.Application.Outbox,
  EF.Infrastructure.Database, EF.Infrastructure.Http, EF.Shared.Logging;

type
  TAppServices = class
  private
    FSession: IDbSession;
    FUow: IUnitOfWork;
    FClock: IClock;
    FLog: ILogger;
    FCtx: TUserContext;
    FReadModel: IReadModel;
    FSales: TSalesService;
    FInvoicing: TInvoicingService;
    FReceivables: TReceivableService;
    FStock: TStockService;
    FPurchases: TPurchaseService;
    FCatalog: TCatalogService;
    FAuth: TAuthService;
  public
    constructor Create(const ASession: IDbSession; const ACtx: TUserContext; const AClock: IClock; const ALog: ILogger);
    destructor Destroy; override;
    function NewOutboxWorker(const APublisher: IEventPublisher; const AMaxAttempts: Integer = 8): TOutboxWorker;
    property Session: IDbSession read FSession;
    property Uow: IUnitOfWork read FUow;
    property Clock: IClock read FClock;
    property Context: TUserContext read FCtx;
    property ReadModel: IReadModel read FReadModel;
    property Sales: TSalesService read FSales;
    property Invoicing: TInvoicingService read FInvoicing;
    property Receivables: TReceivableService read FReceivables;
    property Stock: TStockService read FStock;
    property Purchases: TPurchaseService read FPurchases;
    property Catalog: TCatalogService read FCatalog;
    property Auth: TAuthService read FAuth;
  end;

function NewAuthUow(const ASession: IDbSession): IUnitOfWork;
function NewHttpTransport: IHttpTransport;

implementation

uses
  {$IFDEF FPC}
  EF.Infrastructure.Http.Fcl,
  {$ELSE}
  EF.Infrastructure.Http.Net,
  {$ENDIF}
  EF.Infrastructure.UnitOfWork, EF.Infrastructure.Reporting;

constructor TAppServices.Create(const ASession: IDbSession; const ACtx: TUserContext; const AClock: IClock; const ALog: ILogger);
begin
  inherited Create;
  FSession := ASession;
  FCtx := ACtx;
  FClock := AClock;
  FLog := ALog;
  FUow := TUnitOfWork.Create(ASession);
  FReadModel := TReadModel.Create(ASession);
  FSales := TSalesService.Create(FUow, ACtx, AClock, ALog);
  FInvoicing := TInvoicingService.Create(FUow, ACtx, AClock, ALog);
  FReceivables := TReceivableService.Create(FUow, ACtx, AClock, ALog);
  FStock := TStockService.Create(FUow, ACtx, AClock, ALog);
  FPurchases := TPurchaseService.Create(FUow, ACtx, AClock, ALog);
  FCatalog := TCatalogService.Create(FUow, ACtx, AClock, ALog);
  FAuth := TAuthService.Create(FUow, AClock);
end;

destructor TAppServices.Destroy;
begin
  FSales.Free;
  FInvoicing.Free;
  FReceivables.Free;
  FStock.Free;
  FPurchases.Free;
  FCatalog.Free;
  FAuth.Free;
  inherited;
end;

function TAppServices.NewOutboxWorker(const APublisher: IEventPublisher; const AMaxAttempts: Integer): TOutboxWorker;
begin
  Result := TOutboxWorker.Create(FUow, FCtx, FClock, APublisher, AMaxAttempts);
end;

function NewAuthUow(const ASession: IDbSession): IUnitOfWork;
begin
  Result := TUnitOfWork.Create(ASession);
end;

function NewHttpTransport: IHttpTransport;
begin
  {$IFDEF FPC}
  Result := TFclHttpTransport.Create;
  {$ELSE}
  Result := TNetHttpTransport.Create;
  {$ENDIF}
end;

end.
