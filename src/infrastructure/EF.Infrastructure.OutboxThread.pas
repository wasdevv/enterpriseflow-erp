unit EF.Infrastructure.OutboxThread;

{ Worker da outbox em segundo plano, com conexão própria: sessão de banco não é compartilhada
  entre threads, e a tela nunca espera a rede. }

{$I EF.inc}

interface

uses
  SysUtils, Classes, SyncObjs,
  EF.Application.Ports, EF.Infrastructure.Config;

type
  TOutboxThread = class(TThread)
  private
    FConfig: TAppConfig;
    FCtx: TUserContext;
    FWake: TEvent;
    FIntervalMs: Integer;
  protected
    procedure Execute; override;
  public
    LastError: string;
    Cycles: Integer;
    constructor Create(const AConfig: TAppConfig; const ACtx: TUserContext; const AIntervalMs: Integer = 15000);
    destructor Destroy; override;
    procedure Wake;
    procedure Shutdown;
  end;

implementation

uses
  EF.Application.Outbox,
  EF.Infrastructure.Composition, EF.Infrastructure.Database, EF.Infrastructure.Database.Driver,
  EF.Infrastructure.Http, EF.Infrastructure.UnitOfWork, EF.Shared.Logging;

constructor TOutboxThread.Create(const AConfig: TAppConfig; const ACtx: TUserContext; const AIntervalMs: Integer);
begin
  FConfig := AConfig;
  FCtx := ACtx;
  FIntervalMs := AIntervalMs;
  FWake := TEvent.Create(nil, False, False, '');
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TOutboxThread.Destroy;
begin
  FWake.Free;
  inherited;
end;

procedure TOutboxThread.Wake;
begin
  FWake.SetEvent;
end;

procedure TOutboxThread.Shutdown;
begin
  Terminate;
  FWake.SetEvent;
  WaitFor;
  Free;
end;

procedure TOutboxThread.Execute;
var
  LServices: TAppServices;
  LWorker: TOutboxWorker;
  LPublisher: IEventPublisher;
begin
  while not Terminated do
  begin
    { Conexão por ciclo: banco fora do ar não derruba a thread; ela tenta de novo depois. }
    try
      LServices := TAppServices.Create(OpenSession(FConfig.Db), FCtx, TSystemClock.Create, TNullLogger.Create);
      try
        LPublisher := TFiscalApiPublisher.Create(NewHttpTransport, LServices.Uow, TThreadSleeper.Create, TRetryPolicy.Default,
          FConfig.ApiBaseUrl, GetEnvironmentVariable('EF_API_TOKEN'), FConfig.ApiTimeoutMs);
        LWorker := LServices.NewOutboxWorker(LPublisher);
        try
          LWorker.ProcessBatch;
          LastError := '';
        finally
          LWorker.Free;
        end;
        LPublisher := nil;
      finally
        LServices.Free;
      end;
    except
      on E: Exception do
        LastError := E.Message;
    end;
    Inc(Cycles);
    if not Terminated then
      FWake.WaitFor(FIntervalMs);
  end;
end;

end.
