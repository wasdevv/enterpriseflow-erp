unit EF.Application.Outbox;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Application.Ports, EF.Application.Base;

type
  TOutboxRunSummary = record
    Claimed, Delivered, Retried, Dead: Integer;
  end;

  { Publica depois do commit do negócio. A garantia é "pelo menos uma vez": quem recebe
    deduplica pela idempotency key, que é estável entre tentativas. }
  TOutboxWorker = class(TServiceBase)
  private
    FPublisher: IEventPublisher;
    FMaxAttempts: Integer;
  public
    constructor Create(const AUow: IUnitOfWork; const ACtx: TUserContext; const AClock: IClock; const APublisher: IEventPublisher; const AMaxAttempts: Integer = 8);
    function ProcessBatch(const ALimit: Integer = 20): TOutboxRunSummary;
    procedure Requeue(const AEventId: Int64);
  end;

{ Backoff exponencial em minutos, com teto de 60. }
function OutboxBackoffMinutes(const AAttempt: Integer): Integer;

implementation

uses
  EF.Shared.Logging, EF.Shared.Text;

const
  { Posse maior que a duração máxima de uma publicação. Worker que morre libera o evento. }
  CClaimMinutes = 5;

function OutboxBackoffMinutes(const AAttempt: Integer): Integer;
var
  LIndex: Integer;
begin
  Result := 1;
  for LIndex := 2 to AAttempt do
  begin
    Result := Result * 2;
    if Result >= 60 then
      Exit(60);
  end;
end;

constructor TOutboxWorker.Create(const AUow: IUnitOfWork; const ACtx: TUserContext; const AClock: IClock; const APublisher: IEventPublisher; const AMaxAttempts: Integer);
begin
  inherited Create(AUow, ACtx, AClock, nil);
  FPublisher := APublisher;
  FMaxAttempts := AMaxAttempts;
end;

function TOutboxWorker.ProcessBatch(const ALimit: Integer): TOutboxRunSummary;
var
  LEvents: TOutboxEventArray;
  LIndex: Integer;
  LResult: TPublishResult;
  LNow: TDateTime;
  LStart: Int64;
begin
  Result.Claimed := 0;
  Result.Delivered := 0;
  Result.Retried := 0;
  Result.Dead := 0;

  LNow := FClock.Now;
  FUow.StartTransaction;
  try
    LEvents := FUow.Outbox.ClaimDue(ALimit, LNow, LNow + CClaimMinutes / (24 * 60));
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
  Result.Claimed := Length(LEvents);

  for LIndex := 0 to High(LEvents) do
  begin
    FCtx.CorrelationId := LEvents[LIndex].CorrelationId;
    LStart := NowTick;
    { Nenhuma transação aberta durante a rede: serviço lento não prende registro no banco. }
    try
      LResult := FPublisher.Publish(LEvents[LIndex]);
    except
      on E: Exception do
      begin
        LResult.Outcome := poTransientFailure;
        LResult.Detail := E.Message;
      end;
    end;

    LNow := FClock.Now;
    FUow.StartTransaction;
    try
      case LResult.Outcome of
        poDelivered:
          begin
            FUow.Outbox.MarkSent(LEvents[LIndex].Id, LNow);
            Inc(Result.Delivered);
          end;
        poTransientFailure:
          if LEvents[LIndex].Attempts >= FMaxAttempts then
          begin
            FUow.Outbox.MarkDead(LEvents[LIndex].Id, LResult.Detail);
            Inc(Result.Dead);
          end
          else
          begin
            FUow.Outbox.MarkRetry(LEvents[LIndex].Id, LNow + OutboxBackoffMinutes(LEvents[LIndex].Attempts) / (24 * 60), LResult.Detail);
            Inc(Result.Retried);
          end;
        poPermanentFailure:
          begin
            FUow.Outbox.MarkDead(LEvents[LIndex].Id, LResult.Detail);
            Inc(Result.Dead);
          end;
      end;
      FUow.Commit;
    except
      FUow.Rollback;
      raise;
    end;
    if LResult.Outcome <> poDelivered then
      RecordMetric('integration_failed', LEvents[LIndex].EventType + ': ' + LResult.Detail, LStart)
    else
      RecordMetric('integration_delivered', LEvents[LIndex].EventType, LStart);
  end;
end;

procedure TOutboxWorker.Requeue(const AEventId: Int64);
begin
  BeginOperation(PermIntegrationManage);
  FUow.StartTransaction;
  try
    FUow.Outbox.Requeue(AEventId, FClock.Now);
    Audit('outbox.requeued', 'outbox_event', AEventId);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

end.
