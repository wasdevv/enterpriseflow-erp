unit EF.Infrastructure.Http;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Application.Ports;

type
  THttpHeader = record
    Name, Value: string;
  end;
  THttpHeaders = array of THttpHeader;

  THttpRequest = record
    Method, Url, Body: string;
    Headers: THttpHeaders;
    TimeoutMs: Integer;
    IdempotencyKey, CorrelationId: string;
  end;

  THttpResponse = record
    StatusCode: Integer;
    Body: string;
  end;

  { Falha sem resposta HTTP: conexão recusada, queda ou timeout. O efeito no servidor é
    desconhecido; pode ter acontecido. }
  EHttpTransportError = class(Exception);

  IHttpTransport = interface
    function Send(const ARequest: THttpRequest): THttpResponse;
  end;

  ISleeper = interface
    procedure SleepMs(const AMilliseconds: Integer);
  end;

  TThreadSleeper = class(TInterfacedObject, ISleeper)
  public
    procedure SleepMs(const AMilliseconds: Integer);
  end;

  TRetryPolicy = record
    MaxAttempts, BaseDelayMs, MaxDelayMs: Integer;
    class function Default: TRetryPolicy; static;
    function DelayMs(const AAttempt: Integer): Integer;
  end;

  THttpCallResult = record
    Outcome: TPublishOutcome;
    StatusCode, Attempts: Integer;
    Detail, Body: string;
  end;

  { Timeout, retry e registro de cada tentativa. Só repete o que é seguro: GET ou requisição
    com idempotency key. Sem isso, uma falha ambígua não pode ser repetida. }
  TResilientHttpClient = class
  private
    FTransport: IHttpTransport;
    FUow: IUnitOfWork;
    FSleeper: ISleeper;
    FPolicy: TRetryPolicy;
    procedure LogAttempt(const ARequest: THttpRequest; const AAttempt, AStatus, ADurationMs: Integer; const AOutcome, AError, ABody: string);
  public
    constructor Create(const ATransport: IHttpTransport; const AUow: IUnitOfWork; const ASleeper: ISleeper; const APolicy: TRetryPolicy);
    function Execute(const ARequest: THttpRequest): THttpCallResult;
  end;

  { Publica eventos no serviço fiscal simulado (tools/mock_fiscal_api.py). }
  TFiscalApiPublisher = class(TInterfacedObject, IEventPublisher)
  private
    FClient: TResilientHttpClient;
    FBaseUrl, FToken: string;
    FTimeoutMs: Integer;
  public
    constructor Create(const ATransport: IHttpTransport; const AUow: IUnitOfWork; const ASleeper: ISleeper;
      const APolicy: TRetryPolicy; const ABaseUrl, AToken: string; const ATimeoutMs: Integer);
    destructor Destroy; override;
    function Publish(const AEvent: TOutboxEvent): TPublishResult;
  end;

function IsTransientStatus(const AStatus: Integer): Boolean;
function ClassifyStatus(const AStatus: Integer): TPublishOutcome;
function IsSafeToRetry(const ARequest: THttpRequest): Boolean;

implementation

uses
  EF.Shared.Logging, EF.Shared.Text;

procedure TThreadSleeper.SleepMs(const AMilliseconds: Integer);
begin
  Sleep(AMilliseconds);
end;

class function TRetryPolicy.Default: TRetryPolicy;
begin
  Result.MaxAttempts := 3;
  Result.BaseDelayMs := 200;
  Result.MaxDelayMs := 2000;
end;

function TRetryPolicy.DelayMs(const AAttempt: Integer): Integer;
var
  LIndex: Integer;
begin
  Result := BaseDelayMs;
  for LIndex := 2 to AAttempt do
    Result := Result * 2;
  if Result > MaxDelayMs then
    Result := MaxDelayMs;
  { Jitter: evita que vários clientes repitam no mesmo instante. }
  if Result > 1 then
    Result := Result div 2 + Random(Result div 2 + 1);
end;

function IsTransientStatus(const AStatus: Integer): Boolean;
begin
  Result := (AStatus = 408) or (AStatus = 425) or (AStatus = 429) or (AStatus >= 500);
end;

function ClassifyStatus(const AStatus: Integer): TPublishOutcome;
begin
  if (AStatus >= 200) and (AStatus < 300) then
    Result := poDelivered
  else if IsTransientStatus(AStatus) then
    Result := poTransientFailure
  else
    Result := poPermanentFailure;
end;

function IsSafeToRetry(const ARequest: THttpRequest): Boolean;
begin
  Result := SameText(ARequest.Method, 'GET') or (ARequest.IdempotencyKey <> '');
end;

constructor TResilientHttpClient.Create(const ATransport: IHttpTransport; const AUow: IUnitOfWork; const ASleeper: ISleeper; const APolicy: TRetryPolicy);
begin
  inherited Create;
  FTransport := ATransport;
  FUow := AUow;
  FSleeper := ASleeper;
  FPolicy := APolicy;
end;

procedure TResilientHttpClient.LogAttempt(const ARequest: THttpRequest; const AAttempt, AStatus, ADurationMs: Integer; const AOutcome, AError, ABody: string);
var
  LEntry: TIntegrationLogEntry;
begin
  LEntry.CorrelationId := ARequest.CorrelationId;
  LEntry.IdempotencyKey := ARequest.IdempotencyKey;
  LEntry.Method := ARequest.Method;
  LEntry.Url := ARequest.Url;
  LEntry.Outcome := AOutcome;
  LEntry.ErrorMessage := RedactSecrets(AError);
  LEntry.ResponseExcerpt := RedactSecrets(ABody);
  LEntry.Attempt := AAttempt;
  LEntry.HttpStatus := AStatus;
  LEntry.DurationMs := ADurationMs;
  { Cabeçalhos não entram no log, nem por acidente: Authorization vive só em ARequest. }
  FUow.StartTransaction;
  try
    FUow.IntegrationLogs.Add(LEntry);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

function TResilientHttpClient.Execute(const ARequest: THttpRequest): THttpCallResult;
var
  LAttempt, LMaxAttempts: Integer;
  LResponse: THttpResponse;
  LStart: Int64;
begin
  LMaxAttempts := FPolicy.MaxAttempts;
  if not IsSafeToRetry(ARequest) then
    LMaxAttempts := 1;
  Result.Outcome := poTransientFailure;
  Result.StatusCode := 0;
  Result.Attempts := 0;
  Result.Detail := '';
  Result.Body := '';

  for LAttempt := 1 to LMaxAttempts do
  begin
    Result.Attempts := LAttempt;
    LStart := NowTick;
    try
      LResponse := FTransport.Send(ARequest);
      Result.StatusCode := LResponse.StatusCode;
      Result.Body := LResponse.Body;
      Result.Outcome := ClassifyStatus(LResponse.StatusCode);
      case Result.Outcome of
        poDelivered:
          begin
            Result.Detail := '';
            LogAttempt(ARequest, LAttempt, LResponse.StatusCode, ElapsedSince(LStart), 'DELIVERED', '', LResponse.Body);
            Exit;
          end;
        poPermanentFailure:
          begin
            Result.Detail := Format('HTTP %d', [LResponse.StatusCode]);
            LogAttempt(ARequest, LAttempt, LResponse.StatusCode, ElapsedSince(LStart), 'PERMANENT_FAILURE', Result.Detail, LResponse.Body);
            Exit;
          end;
      else
        Result.Detail := Format('HTTP %d', [LResponse.StatusCode]);
        LogAttempt(ARequest, LAttempt, LResponse.StatusCode, ElapsedSince(LStart), 'TRANSIENT_FAILURE', Result.Detail, LResponse.Body);
      end;
    except
      on E: EHttpTransportError do
      begin
        Result.Outcome := poTransientFailure;
        Result.StatusCode := 0;
        Result.Detail := E.Message;
        LogAttempt(ARequest, LAttempt, 0, ElapsedSince(LStart), 'TRANSPORT_FAILURE', E.Message, '');
      end;
    end;
    if LAttempt < LMaxAttempts then
      FSleeper.SleepMs(FPolicy.DelayMs(LAttempt));
  end;
end;

constructor TFiscalApiPublisher.Create(const ATransport: IHttpTransport; const AUow: IUnitOfWork; const ASleeper: ISleeper;
  const APolicy: TRetryPolicy; const ABaseUrl, AToken: string; const ATimeoutMs: Integer);
begin
  inherited Create;
  FClient := TResilientHttpClient.Create(ATransport, AUow, ASleeper, APolicy);
  FBaseUrl := ABaseUrl;
  FToken := AToken;
  FTimeoutMs := ATimeoutMs;
end;

destructor TFiscalApiPublisher.Destroy;
begin
  FClient.Free;
  inherited;
end;

function TFiscalApiPublisher.Publish(const AEvent: TOutboxEvent): TPublishResult;
var
  LRequest: THttpRequest;
  LCall: THttpCallResult;
begin
  LRequest.Method := 'POST';
  LRequest.Url := FBaseUrl + '/v1/events';
  LRequest.Body := TJsonObjectBuilder.New.Str('type', AEvent.EventType).Int('aggregate_id', AEvent.AggregateId).Raw('data', AEvent.Payload).ToJson;
  LRequest.TimeoutMs := FTimeoutMs;
  LRequest.IdempotencyKey := AEvent.IdempotencyKey;
  LRequest.CorrelationId := AEvent.CorrelationId;
  SetLength(LRequest.Headers, 3);
  LRequest.Headers[0].Name := 'Content-Type';
  LRequest.Headers[0].Value := 'application/json';
  LRequest.Headers[1].Name := 'Idempotency-Key';
  LRequest.Headers[1].Value := AEvent.IdempotencyKey;
  LRequest.Headers[2].Name := 'X-Correlation-Id';
  LRequest.Headers[2].Value := AEvent.CorrelationId;
  if FToken <> '' then
  begin
    SetLength(LRequest.Headers, 4);
    LRequest.Headers[3].Name := 'Authorization';
    LRequest.Headers[3].Value := 'Bearer ' + FToken;
  end;
  LCall := FClient.Execute(LRequest);
  Result.Outcome := LCall.Outcome;
  Result.Detail := LCall.Detail;
end;

end.
