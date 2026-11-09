unit EF.Tests.Spawn;

{ Inicia processos reais para o teste de corrida entre processos. }

{$I EF.inc}

interface

uses
  SysUtils, Classes;

type
  TSpawned = class
  private
    {$IFDEF FPC}
    FProcess: TObject;
    {$ELSE}
    FHandle: THandle;
    {$ENDIF}
  public
    constructor Start(const AExecutable: string; const AArguments: array of string);
    destructor Destroy; override;
    function WaitExitCode: Integer;
  end;

function SiblingExecutable(const AName: string): string;

implementation

uses
  {$IFDEF FPC}
  Process;
  {$ELSE}
  Winapi.Windows;
  {$ENDIF}

function SiblingExecutable(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + AName {$IFDEF MSWINDOWS} + '.exe' {$ENDIF};
end;

constructor TSpawned.Start(const AExecutable: string; const AArguments: array of string);
var
  LIndex: Integer;
{$IFDEF FPC}
  LProcess: TProcess;
{$ELSE}
  LCommand: string;
  LStartup: TStartupInfo;
  LInfo: TProcessInformation;
{$ENDIF}
begin
  inherited Create;
  {$IFDEF FPC}
  LProcess := TProcess.Create(nil);
  LProcess.Executable := AExecutable;
  for LIndex := Low(AArguments) to High(AArguments) do
    LProcess.Parameters.Add(AArguments[LIndex]);
  LProcess.Options := [];
  LProcess.Execute;
  FProcess := LProcess;
  {$ELSE}
  LCommand := '"' + AExecutable + '"';
  for LIndex := Low(AArguments) to High(AArguments) do
    LCommand := LCommand + ' "' + AArguments[LIndex] + '"';
  UniqueString(LCommand);
  FillChar(LStartup, SizeOf(LStartup), 0);
  LStartup.cb := SizeOf(LStartup);
  if not CreateProcess(nil, PChar(LCommand), nil, nil, False, 0, nil, nil, LStartup, LInfo) then
    RaiseLastOSError;
  CloseHandle(LInfo.hThread);
  FHandle := LInfo.hProcess;
  {$ENDIF}
end;

destructor TSpawned.Destroy;
begin
  {$IFDEF FPC}
  FProcess.Free;
  {$ELSE}
  CloseHandle(FHandle);
  {$ENDIF}
  inherited;
end;

function TSpawned.WaitExitCode: Integer;
{$IFNDEF FPC}
var
  LCode: DWORD;
{$ENDIF}
begin
  {$IFDEF FPC}
  TProcess(FProcess).WaitOnExit;
  Result := TProcess(FProcess).ExitStatus;
  {$ELSE}
  WaitForSingleObject(FHandle, INFINITE);
  GetExitCodeProcess(FHandle, LCode);
  Result := Integer(LCode);
  {$ENDIF}
end;

end.
