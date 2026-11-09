unit EF.Shared.Logging;

{$I EF.inc}

interface

uses
  SysUtils, Classes, SyncObjs;

type
  TLogLevel = (llDebug, llInfo, llWarn, llError);

  ILogger = interface
    procedure Log(const ALevel: TLogLevel; const AEvent, ACorrelationId, AFieldsJson: string);
  end;

  { Uma linha JSON por evento. O texto passa por RedactSecrets antes de ir para o disco. }
  TJsonFileLogger = class(TInterfacedObject, ILogger)
  private
    FLock: TCriticalSection;
    FPath: string;
  public
    constructor Create(const APath: string);
    destructor Destroy; override;
    procedure Log(const ALevel: TLogLevel; const AEvent, ACorrelationId, AFieldsJson: string);
  end;

  TNullLogger = class(TInterfacedObject, ILogger)
  public
    procedure Log(const ALevel: TLogLevel; const AEvent, ACorrelationId, AFieldsJson: string);
  end;

function ElapsedSince(const AStartTick: Int64): Int64;
function NowTick: Int64;

implementation

uses
  EF.Shared.Text;

const
  CLevels: array [TLogLevel] of string = ('debug', 'info', 'warn', 'error');

function NowTick: Int64;
begin
  {$IFDEF FPC}
  Result := Int64(GetTickCount64);
  {$ELSE}
  Result := Int64(TThread.GetTickCount64);
  {$ENDIF}
end;

function ElapsedSince(const AStartTick: Int64): Int64;
begin
  Result := NowTick - AStartTick;
end;

constructor TJsonFileLogger.Create(const APath: string);
begin
  inherited Create;
  FPath := APath;
  FLock := TCriticalSection.Create;
end;

destructor TJsonFileLogger.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TJsonFileLogger.Log(const ALevel: TLogLevel; const AEvent, ACorrelationId, AFieldsJson: string);
var
  LLine: RawByteString;
  LStream: TFileStream;
  LBuilder: TJsonObjectBuilder;
begin
  LBuilder := TJsonObjectBuilder.New
    .Str('ts', IsoTimestamp(Now))
    .Str('level', CLevels[ALevel])
    .Str('event', AEvent)
    .Str('correlation_id', ACorrelationId);
  if AFieldsJson <> '' then
    LBuilder := LBuilder.Raw('fields', RedactSecrets(AFieldsJson));
  LLine := UTF8Encode(LBuilder.ToJson + sLineBreak);

  FLock.Acquire;
  try
    if FileExists(FPath) then
      LStream := TFileStream.Create(FPath, fmOpenReadWrite or fmShareDenyNone)
    else
      LStream := TFileStream.Create(FPath, fmCreate);
    try
      LStream.Seek(0, soEnd);
      LStream.WriteBuffer(LLine[1], Length(LLine));
    finally
      LStream.Free;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TNullLogger.Log(const ALevel: TLogLevel; const AEvent, ACorrelationId, AFieldsJson: string);
begin
end;

end.
