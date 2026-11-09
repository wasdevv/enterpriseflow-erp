unit EF.Tests.Integration;

{ Outbox e HTTP contra um servidor real (tools/mock_fiscal_api.py), com falhas roteirizadas. }

{$I EF.inc}
{$M+}

interface

uses
  SysUtils, DUnitX.TestFramework;

type
  TOutboxIntegrationTests = class(TObject)
  published
    procedure DeliversAndMarksSent;
    procedure TransientFailuresAreRetriedWithoutDuplicating;
    procedure LostResponseAfterServerAppliedDoesNotDuplicate;
    procedure TimeoutKeepsInvoiceConsistentAndEventRetryable;
    procedure PermanentFailureGoesDeadWithoutRetryAndCanBeRequeued;
    procedure ReprocessingAlreadyDeliveredEventHasNoEffect;
    procedure ClaimSkipsEventsHeldByAnotherWorker;
    procedure ClaimedEventIsNotTakenUntilClaimExpires;
    procedure AttemptsExhaustedGoesDead;
    procedure LogsNeverContainTheToken;
    procedure NoTransactionIsOpenDuringTheCall;
  end;

  THttpPolicyTests = class(TObject)
  published
    procedure PostWithoutKeyIsNotRetriedOnAmbiguousFailure;
    procedure PostWithKeyIsRetriedOnTransportFailure;
    procedure GetIsRetried;
    procedure PermanentStatusIsNotRetried;
    procedure StatusClassification;
    procedure BackoffGrowsAndHasCeiling;
  end;

implementation

uses
  EF.Application.Ports, EF.Application.Outbox, EF.Application.Finance,
  EF.Infrastructure.Composition, EF.Infrastructure.Database, EF.Infrastructure.Database.Driver,
  EF.Infrastructure.Http, EF.Infrastructure.Repositories.Support, EF.Infrastructure.UnitOfWork,
  EF.Tests.Support, EF.Shared.Text;

type
  TNoSleep = class(TInterfacedObject, ISleeper)
  public
    procedure SleepMs(const AMilliseconds: Integer);
  end;

  TScriptedTransport = class(TInterfacedObject, IHttpTransport)
  private
    FStatus: array of Integer;
    FNext: Integer;
  public
    Calls: Integer;
    constructor Create(const AStatus: array of Integer);
    function Send(const ARequest: THttpRequest): THttpResponse;
  end;

  { Verifica, durante a chamada de rede, se a sessão tem transação aberta. }
  TTransactionProbeTransport = class(TInterfacedObject, IHttpTransport)
  private
    FUow: IUnitOfWork;
    FInner: IHttpTransport;
  public
    SawOpenTransaction: Boolean;
    constructor Create(const AUow: IUnitOfWork; const AInner: IHttpTransport);
    function Send(const ARequest: THttpRequest): THttpResponse;
  end;

procedure TNoSleep.SleepMs(const AMilliseconds: Integer);
begin
end;

constructor TScriptedTransport.Create(const AStatus: array of Integer);
var
  LIndex: Integer;
begin
  inherited Create;
  SetLength(FStatus, Length(AStatus));
  for LIndex := 0 to High(AStatus) do
    FStatus[LIndex] := AStatus[LIndex];
end;

function TScriptedTransport.Send(const ARequest: THttpRequest): THttpResponse;
var
  LStatus: Integer;
begin
  Inc(Calls);
  LStatus := FStatus[FNext];
  if FNext < High(FStatus) then
    Inc(FNext);
  { Status zero no roteiro representa queda de conexão. }
  if LStatus = 0 then
    raise EHttpTransportError.Create('Conexão perdida');
  Result.StatusCode := LStatus;
  Result.Body := '{}';
end;

constructor TTransactionProbeTransport.Create(const AUow: IUnitOfWork; const AInner: IHttpTransport);
begin
  inherited Create;
  FUow := AUow;
  FInner := AInner;
end;

function TTransactionProbeTransport.Send(const ARequest: THttpRequest): THttpResponse;
begin
  if FUow.InTransaction then
    SawOpenTransaction := True;
  Result := FInner.Send(ARequest);
end;

function ApiUrl: string;
begin
  Result := GetEnvironmentVariable('EF_TEST_API_URL');
  if Result = '' then
    raise Exception.Create('EF_TEST_API_URL não configurada. Use scripts/test.sh.');
end;

function CallAdmin(const AMethod, APath, ABody: string): string;
var
  LRequest: THttpRequest;
begin
  LRequest.Method := AMethod;
  LRequest.Url := ApiUrl + APath;
  LRequest.Body := ABody;
  LRequest.TimeoutMs := 5000;
  LRequest.IdempotencyKey := '';
  LRequest.CorrelationId := '';
  SetLength(LRequest.Headers, 1);
  LRequest.Headers[0].Name := 'Content-Type';
  LRequest.Headers[0].Value := 'application/json';
  Result := NewHttpTransport.Send(LRequest).Body;
end;

procedure ScriptResponses(const AJson: string);
begin
  CallAdmin('POST', '/__admin/reset', '{}');
  if AJson <> '' then
    CallAdmin('POST', '/__admin/script', AJson);
end;

function EffectsOf(const AKey: string): string;
begin
  Result := CallAdmin('GET', '/__admin/effects?key=' + AKey, '');
end;

function ReceivedCount: string;
begin
  Result := CallAdmin('GET', '/__admin/received', '');
end;

{ Fatura real, com o evento pendente na outbox. Limpa o que outros testes deixaram. }
function PendingInvoiceEvent(const AEnv: ITestEnv; out AKey: string): Int64;
var
  LOrder: Int64;
  LInvoice: TInvoiceResult;
begin
  AEnv.ExecuteSql('UPDATE outbox_events SET status = ''SENT'' WHERE status = ''PENDING''', []);
  LOrder := ShippedOrder(AEnv, '10,00');
  LInvoice := AEnv.App.Invoicing.InvoiceOrder(LOrder, Date + 30);
  AKey := 'invoice-issued-' + IntToStr(LInvoice.InvoiceId);
  Result := StrToInt64(AEnv.QueryText('SELECT id FROM outbox_events WHERE idempotency_key = :k', [P('k', AKey)]));
end;

function NewPublisher(const AEnv: ITestEnv; const ATransport: IHttpTransport; const ATimeoutMs: Integer = 3000; const AToken: string = ''): IEventPublisher;
var
  LPolicy: TRetryPolicy;
begin
  LPolicy.MaxAttempts := 3;
  LPolicy.BaseDelayMs := 1;
  LPolicy.MaxDelayMs := 2;
  Result := TFiscalApiPublisher.Create(ATransport, AEnv.App.Uow, TNoSleep.Create, LPolicy, ApiUrl, AToken, ATimeoutMs);
end;

function StatusOfEvent(const AEnv: ITestEnv; const AEventId: Int64): string;
begin
  Result := AEnv.QueryText('SELECT status FROM outbox_events WHERE id = :id', [P('id', AEventId)]);
end;

procedure RunWorker(const AEnv: ITestEnv; const APublisher: IEventPublisher; const AMaxAttempts: Integer = 8);
var
  LWorker: TOutboxWorker;
begin
  LWorker := AEnv.App.NewOutboxWorker(APublisher, AMaxAttempts);
  try
    LWorker.ProcessBatch;
  finally
    LWorker.Free;
  end;
end;

procedure TOutboxIntegrationTests.DeliversAndMarksSent;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey: string;
begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  ScriptResponses('');
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport));
  Assert.AreEqual('SENT', StatusOfEvent(LEnv, LEvent));
  Assert.AreEqual('1', EffectsOf(LKey));
  Assert.IsTrue(LEnv.QueryText('SELECT sent_at FROM outbox_events WHERE id = :id', [P('id', LEvent)]) <> '');
  Assert.AreEqual(1, LEnv.CountRows('SELECT id FROM integration_logs WHERE idempotency_key = :k AND outcome = ''DELIVERED''', [P('k', LKey)]));
end;

procedure TOutboxIntegrationTests.TransientFailuresAreRetriedWithoutDuplicating;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey: string;
begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  ScriptResponses('[{"status":503},{"status":429}]');
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport));
  Assert.AreEqual('SENT', StatusOfEvent(LEnv, LEvent));
  Assert.AreEqual('3', ReceivedCount, 'Duas falhas e o sucesso');
  Assert.AreEqual('1', EffectsOf(LKey));
  Assert.AreEqual(3, LEnv.CountRows('SELECT id FROM integration_logs WHERE idempotency_key = :k', [P('k', LKey)]));
end;

procedure TOutboxIntegrationTests.LostResponseAfterServerAppliedDoesNotDuplicate;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey: string;
begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  { O servidor aplica e responde 500: para o cliente, o resultado é desconhecido. }
  ScriptResponses('[{"status":500,"apply":true}]');
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport));
  Assert.AreEqual('SENT', StatusOfEvent(LEnv, LEvent));
  Assert.AreEqual('2', ReceivedCount);
  Assert.AreEqual('1', EffectsOf(LKey), 'A idempotency key impede a segunda aplicação');
end;

procedure TOutboxIntegrationTests.TimeoutKeepsInvoiceConsistentAndEventRetryable;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey, LInvoiceStatus: string;
  LPolicy: TRetryPolicy;
  LPublisher: IEventPublisher;
begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  ScriptResponses('[{"delay_ms":1500}]');
  LPolicy.MaxAttempts := 1;
  LPolicy.BaseDelayMs := 1;
  LPolicy.MaxDelayMs := 1;
  LPublisher := TFiscalApiPublisher.Create(NewHttpTransport, LEnv.App.Uow, TNoSleep.Create, LPolicy, ApiUrl, '', 300);
  RunWorker(LEnv, LPublisher);
  LInvoiceStatus := LEnv.QueryText(
    'SELECT o.status FROM sales_orders o JOIN invoices i ON i.sales_order_id = o.id JOIN outbox_events e ON e.aggregate_id = i.id WHERE e.id = :id', [P('id', LEvent)]);
  Assert.AreEqual('INVOICED', LInvoiceStatus, 'Falha de rede não desfaz nem corrompe o faturamento');
  Assert.AreEqual('PENDING', StatusOfEvent(LEnv, LEvent));
  Assert.AreEqual('1', LEnv.QueryText('SELECT attempts FROM outbox_events WHERE id = :id', [P('id', LEvent)]));
  Assert.IsTrue(LEnv.QueryText('SELECT last_error FROM outbox_events WHERE id = :id', [P('id', LEvent)]) <> '');

  { Antecipa o backoff e reprocessa: o evento é entregue sem efeito duplicado. }
  LEnv.ExecuteSql('UPDATE outbox_events SET next_attempt_at = DATEADD(-1 MINUTE TO LOCALTIMESTAMP) WHERE id = :id', [P('id', LEvent)]);
  Sleep(1500);
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport));
  Assert.AreEqual('SENT', StatusOfEvent(LEnv, LEvent));
  Assert.AreEqual('1', EffectsOf(LKey));
end;

procedure TOutboxIntegrationTests.PermanentFailureGoesDeadWithoutRetryAndCanBeRequeued;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey: string;
  LWorker: TOutboxWorker;
begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  ScriptResponses('[{"status":422}]');
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport));
  Assert.AreEqual('DEAD', StatusOfEvent(LEnv, LEvent));
  Assert.AreEqual('1', ReceivedCount, '4xx permanente não é repetido');
  LWorker := LEnv.App.NewOutboxWorker(NewPublisher(LEnv, NewHttpTransport));
  try
    LWorker.Requeue(LEvent);
  finally
    LWorker.Free;
  end;
  Assert.AreEqual('PENDING', StatusOfEvent(LEnv, LEvent));
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport));
  Assert.AreEqual('SENT', StatusOfEvent(LEnv, LEvent));
  Assert.AreEqual('1', EffectsOf(LKey));
end;

procedure TOutboxIntegrationTests.ReprocessingAlreadyDeliveredEventHasNoEffect;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey: string;
begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  ScriptResponses('');
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport));
  { Simula queda do worker entre a resposta HTTP e o commit do status. }
  LEnv.ExecuteSql('UPDATE outbox_events SET status = ''PENDING'', claimed_until = NULL, next_attempt_at = DATEADD(-1 MINUTE TO LOCALTIMESTAMP) WHERE id = :id', [P('id', LEvent)]);
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport));
  Assert.AreEqual('SENT', StatusOfEvent(LEnv, LEvent));
  Assert.AreEqual('2', ReceivedCount, 'O evento foi mesmo reenviado');
  Assert.AreEqual('1', EffectsOf(LKey), 'Sem efeito duplicado');
end;

procedure TOutboxIntegrationTests.ClaimSkipsEventsHeldByAnotherWorker;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey: string;
  LOther: IDbSession;
  LOtherUow: IUnitOfWork;
  LMine, LTheirs: TOutboxEventArray;
  LStart: Int64;
  LIndex: Integer;
  LFound: Boolean;
begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  LEnv.App.Uow.StartTransaction;
  try
    LMine := LEnv.App.Uow.Outbox.ClaimDue(50, Now, Now + 1 / 24);
    LFound := False;
    for LIndex := 0 to High(LMine) do
      if LMine[LIndex].Id = LEvent then
        LFound := True;
    Assert.IsTrue(LFound, 'O primeiro worker pegou o evento');

    { A transação do primeiro segue aberta, com a linha bloqueada. }
    LOther := OpenSession(LEnv.Config);
    LOtherUow := TUnitOfWork.Create(LOther);
    LOtherUow.StartTransaction;
    try
      LStart := GetTickCount64;
      LTheirs := LOtherUow.Outbox.ClaimDue(50, Now, Now + 1 / 24);
      for LIndex := 0 to High(LTheirs) do
        Assert.IsTrue(LTheirs[LIndex].Id <> LEvent, 'O segundo worker não pode pegar o mesmo evento');
      Assert.IsTrue(GetTickCount64 - LStart < 2000, 'SKIP LOCKED pula em vez de esperar o bloqueio');
    finally
      LOtherUow.Rollback;
    end;
  finally
    LEnv.App.Uow.Rollback;
  end;
end;

procedure TOutboxIntegrationTests.ClaimedEventIsNotTakenUntilClaimExpires;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey: string;
  LEvents: TOutboxEventArray;
  LIndex: Integer;
  LFound: Boolean;

  function ClaimFinds(const ANow: TDateTime): Boolean;
  var
    LInner: Integer;
  begin
    Result := False;
    LEnv.App.Uow.StartTransaction;
    try
      LEvents := LEnv.App.Uow.Outbox.ClaimDue(50, ANow, ANow + 5 / (24 * 60));
      LEnv.App.Uow.Commit;
    except
      LEnv.App.Uow.Rollback;
      raise;
    end;
    for LInner := 0 to High(LEvents) do
      if LEvents[LInner].Id = LEvent then
        Result := True;
  end;

begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  Assert.IsTrue(ClaimFinds(Now), 'Primeira posse');
  Assert.IsFalse(ClaimFinds(Now + 1 / (24 * 60)), 'Um minuto depois, ainda em posse');
  LFound := ClaimFinds(Now + 10 / (24 * 60));
  Assert.IsTrue(LFound, 'Worker que morreu libera o evento quando a posse expira');
  LIndex := StrToInt(LEnv.QueryText('SELECT attempts FROM outbox_events WHERE id = :id', [P('id', LEvent)]));
  Assert.AreEqual(2, LIndex);
end;

procedure TOutboxIntegrationTests.AttemptsExhaustedGoesDead;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey: string;
begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  ScriptResponses('[{"status":503},{"status":503},{"status":503}]');
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport), 1);
  Assert.AreEqual('DEAD', StatusOfEvent(LEnv, LEvent));
  Assert.IsTrue(LEnv.CountRows('SELECT id FROM metric_events WHERE metric = ''integration_failed''', []) > 0);
end;

procedure TOutboxIntegrationTests.LogsNeverContainTheToken;
var
  LEnv: ITestEnv;
  LEvent: Int64;
  LKey, LExcerpt: string;
begin
  LEnv := NewTestEnv;
  LEvent := PendingInvoiceEvent(LEnv, LKey);
  ScriptResponses('[{"status":422,"echo_auth":true}]');
  RunWorker(LEnv, NewPublisher(LEnv, NewHttpTransport, 3000, 'super-secreto-123'));
  Assert.AreEqual('DEAD', StatusOfEvent(LEnv, LEvent));
  LExcerpt := LEnv.QueryText('SELECT response_excerpt FROM integration_logs WHERE idempotency_key = :k', [P('k', LKey)]);
  Assert.IsTrue(LExcerpt <> '', 'O corpo foi registrado');
  Assert.IsTrue(Pos('super-secreto-123', LExcerpt) = 0, 'Token ecoado pelo servidor não pode ir ao log: ' + LExcerpt);
end;

procedure TOutboxIntegrationTests.NoTransactionIsOpenDuringTheCall;
var
  LEnv: ITestEnv;
  LKey: string;
  LProbe: TTransactionProbeTransport;
  LTransport: IHttpTransport;
begin
  LEnv := NewTestEnv;
  PendingInvoiceEvent(LEnv, LKey);
  ScriptResponses('');
  LProbe := TTransactionProbeTransport.Create(LEnv.App.Uow, NewHttpTransport);
  LTransport := LProbe;
  RunWorker(LEnv, NewPublisher(LEnv, LTransport));
  Assert.IsFalse(LProbe.SawOpenTransaction, 'Chamada de rede com transação SQL aberta prenderia registros');
end;

function BuildRequest(const AMethod, AKey: string): THttpRequest;
begin
  Result.Method := AMethod;
  Result.Url := 'http://exemplo.invalid/x';
  Result.Body := '';
  Result.TimeoutMs := 100;
  Result.IdempotencyKey := AKey;
  Result.CorrelationId := '';
  SetLength(Result.Headers, 0);
end;

function NewClient(const AEnv: ITestEnv; const ATransport: IHttpTransport): TResilientHttpClient;
var
  LPolicy: TRetryPolicy;
begin
  LPolicy.MaxAttempts := 3;
  LPolicy.BaseDelayMs := 1;
  LPolicy.MaxDelayMs := 2;
  Result := TResilientHttpClient.Create(ATransport, AEnv.App.Uow, TNoSleep.Create, LPolicy);
end;

procedure THttpPolicyTests.PostWithoutKeyIsNotRetriedOnAmbiguousFailure;
var
  LEnv: ITestEnv;
  LTransport: TScriptedTransport;
  LHolder: IHttpTransport;
  LClient: TResilientHttpClient;
begin
  LEnv := NewTestEnv;
  LTransport := TScriptedTransport.Create([0, 200]);
  LHolder := LTransport;
  LClient := NewClient(LEnv, LHolder);
  try
    LClient.Execute(BuildRequest('POST', ''));
  finally
    LClient.Free;
  end;
  Assert.AreEqual(1, LTransport.Calls, 'O servidor pode ter aplicado: repetir duplicaria');
end;

procedure THttpPolicyTests.PostWithKeyIsRetriedOnTransportFailure;
var
  LEnv: ITestEnv;
  LTransport: TScriptedTransport;
  LHolder: IHttpTransport;
  LClient: TResilientHttpClient;
  LResult: THttpCallResult;
begin
  LEnv := NewTestEnv;
  LTransport := TScriptedTransport.Create([0, 200]);
  LHolder := LTransport;
  LClient := NewClient(LEnv, LHolder);
  try
    LResult := LClient.Execute(BuildRequest('POST', 'chave'));
  finally
    LClient.Free;
  end;
  Assert.AreEqual(2, LTransport.Calls);
  Assert.IsTrue(LResult.Outcome = poDelivered);
end;

procedure THttpPolicyTests.GetIsRetried;
var
  LEnv: ITestEnv;
  LTransport: TScriptedTransport;
  LHolder: IHttpTransport;
  LClient: TResilientHttpClient;
begin
  LEnv := NewTestEnv;
  LTransport := TScriptedTransport.Create([503, 503, 200]);
  LHolder := LTransport;
  LClient := NewClient(LEnv, LHolder);
  try
    LClient.Execute(BuildRequest('GET', ''));
  finally
    LClient.Free;
  end;
  Assert.AreEqual(3, LTransport.Calls);
end;

procedure THttpPolicyTests.PermanentStatusIsNotRetried;
var
  LEnv: ITestEnv;
  LTransport: TScriptedTransport;
  LHolder: IHttpTransport;
  LClient: TResilientHttpClient;
  LResult: THttpCallResult;
begin
  LEnv := NewTestEnv;
  LTransport := TScriptedTransport.Create([400, 200]);
  LHolder := LTransport;
  LClient := NewClient(LEnv, LHolder);
  try
    LResult := LClient.Execute(BuildRequest('POST', 'chave'));
  finally
    LClient.Free;
  end;
  Assert.AreEqual(1, LTransport.Calls);
  Assert.IsTrue(LResult.Outcome = poPermanentFailure);
end;

procedure THttpPolicyTests.StatusClassification;
begin
  Assert.IsTrue(ClassifyStatus(200) = poDelivered);
  Assert.IsTrue(ClassifyStatus(201) = poDelivered);
  Assert.IsTrue(ClassifyStatus(429) = poTransientFailure);
  Assert.IsTrue(ClassifyStatus(408) = poTransientFailure);
  Assert.IsTrue(ClassifyStatus(500) = poTransientFailure);
  Assert.IsTrue(ClassifyStatus(503) = poTransientFailure);
  Assert.IsTrue(ClassifyStatus(404) = poPermanentFailure);
  Assert.IsTrue(ClassifyStatus(422) = poPermanentFailure);
end;

procedure THttpPolicyTests.BackoffGrowsAndHasCeiling;
var
  LPolicy: TRetryPolicy;
begin
  LPolicy.MaxAttempts := 5;
  LPolicy.BaseDelayMs := 100;
  LPolicy.MaxDelayMs := 1000;
  Assert.IsTrue(LPolicy.DelayMs(1) <= 100);
  Assert.IsTrue(LPolicy.DelayMs(1) >= 50);
  Assert.IsTrue(LPolicy.DelayMs(10) <= 1000);
  Assert.IsTrue(LPolicy.DelayMs(10) >= 500);
  Assert.AreEqual(1, OutboxBackoffMinutes(1));
  Assert.AreEqual(4, OutboxBackoffMinutes(3));
  Assert.AreEqual(60, OutboxBackoffMinutes(20));
end;

initialization
  TDUnitX.RegisterTestFixture(TOutboxIntegrationTests);
  TDUnitX.RegisterTestFixture(THttpPolicyTests);

end.
