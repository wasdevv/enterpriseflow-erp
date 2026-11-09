program RunHidden;

{ Só Windows: executa um programa numa área de trabalho oculta, para o roteiro de telas não abrir
  janelas nem roubar o foco de quem está usando o computador. }

{$MODE DELPHI}
{$H+}

uses
  Windows, SysUtils;

function CreateDesktopW(lpszDesktop, lpszDevice: PWideChar; pDevmode: Pointer; dwFlags, dwDesiredAccess: DWORD; lpsa: Pointer): THandle; stdcall; external 'user32' name 'CreateDesktopW';
function CloseDesktop(hDesktop: THandle): BOOL; stdcall; external 'user32' name 'CloseDesktop';

const
  CDesktop: UnicodeString = 'EnterpriseFlowVerificacao';
  CTimeoutMs = 240000;
var
  LDesktop: THandle;
  LStartup: TStartupInfoW;
  LProcess: TProcessInformation;
  LCommand: UnicodeString;
  LIndex: Integer;
  LCode: DWORD;
begin
  LDesktop := CreateDesktopW(PWideChar(CDesktop), nil, nil, 0, GENERIC_ALL, nil);
  if LDesktop = 0 then
  begin
    WriteLn('Falha ao criar a área de trabalho oculta: ', GetLastError);
    Halt(2);
  end;
  LCommand := '"' + UnicodeString(ParamStr(1)) + '"';
  for LIndex := 2 to ParamCount do
    LCommand := LCommand + ' "' + UnicodeString(ParamStr(LIndex)) + '"';
  FillChar(LStartup, SizeOf(LStartup), 0);
  LStartup.cb := SizeOf(LStartup);
  LStartup.lpDesktop := PWideChar(CDesktop);
  LStartup.dwFlags := STARTF_USESTDHANDLES;
  LStartup.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  LStartup.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  LStartup.hStdError := GetStdHandle(STD_ERROR_HANDLE);
  if not CreateProcessW(nil, PWideChar(LCommand), nil, nil, True, 0, nil, nil, LStartup, LProcess) then
  begin
    WriteLn('Falha ao iniciar o programa: ', GetLastError);
    Halt(2);
  end;
  if WaitForSingleObject(LProcess.hProcess, CTimeoutMs) = WAIT_TIMEOUT then
  begin
    TerminateProcess(LProcess.hProcess, 124);
    WriteLn('Tempo esgotado no roteiro de telas.');
  end;
  GetExitCodeProcess(LProcess.hProcess, LCode);
  CloseHandle(LProcess.hThread);
  CloseHandle(LProcess.hProcess);
  CloseDesktop(LDesktop);
  Halt(LCode);
end.
