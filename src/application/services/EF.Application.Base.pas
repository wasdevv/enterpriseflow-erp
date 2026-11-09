unit EF.Application.Base;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Application.Ports, EF.Shared.Logging;

type
  TServiceBase = class
  protected
    FUow: IUnitOfWork;
    FCtx: TUserContext;
    FClock: IClock;
    FLog: ILogger;
    { Confere a permissão e abre um identificador de correlação para esta operação. }
    procedure BeginOperation(const APermission: string);
    procedure Audit(const AAction, AEntityType: string; const AEntityId: Int64; const ADetailsJson: string = '');
    { Em transação própria: tem de sobreviver ao rollback do negócio e nunca derrubá-lo. }
    procedure RecordMetric(const AMetric, ADetail: string; const AStartTick: Int64);
    procedure LogEvent(const ALevel: TLogLevel; const AEvent, AFieldsJson: string);
  public
    constructor Create(const AUow: IUnitOfWork; const ACtx: TUserContext; const AClock: IClock; const ALog: ILogger);
    function LastCorrelationId: string;
  end;

implementation

uses
  EF.Domain.Exceptions, EF.Shared.Text;

constructor TServiceBase.Create(const AUow: IUnitOfWork; const ACtx: TUserContext; const AClock: IClock; const ALog: ILogger);
begin
  inherited Create;
  FUow := AUow;
  FCtx := ACtx;
  FClock := AClock;
  FLog := ALog;
end;

function TServiceBase.LastCorrelationId: string;
begin
  Result := FCtx.CorrelationId;
end;

procedure TServiceBase.BeginOperation(const APermission: string);
begin
  if not FCtx.Has(APermission) then
    raise EPermissionDenied.CreateFmt('Usuário "%s" não tem a permissão "%s".', [FCtx.Username, APermission]);
  FCtx.CorrelationId := NewCorrelationId;
end;

procedure TServiceBase.Audit(const AAction, AEntityType: string; const AEntityId: Int64; const ADetailsJson: string);
begin
  FUow.Audit.Add(FCtx.UserId, AAction, AEntityType, AEntityId, FCtx.CorrelationId, ADetailsJson);
end;

procedure TServiceBase.RecordMetric(const AMetric, ADetail: string; const AStartTick: Int64);
begin
  try
    FUow.StartTransaction;
    try
      FUow.Metrics.Add(AMetric, FCtx.CorrelationId, ADetail, ElapsedSince(AStartTick));
      FUow.Commit;
    except
      FUow.Rollback;
      raise;
    end;
  except
    on E: Exception do
      LogEvent(llWarn, 'metric.write_failed', TJsonObjectBuilder.New.Str('metric', AMetric).Str('error', E.Message).ToJson);
  end;
end;

procedure TServiceBase.LogEvent(const ALevel: TLogLevel; const AEvent, AFieldsJson: string);
begin
  if FLog <> nil then
    FLog.Log(ALevel, AEvent, FCtx.CorrelationId, AFieldsJson);
end;

end.
