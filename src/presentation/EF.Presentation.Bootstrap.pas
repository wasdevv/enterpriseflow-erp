unit EF.Presentation.Bootstrap;

{$I EF.inc}

interface

{ Monta tudo a partir da configuração: conexão, login, serviços, worker e janela principal. }
procedure RunApplication;

implementation

uses
  SysUtils, Forms, Dialogs,
  EF.Application.Ports, EF.Application.Catalog,
  EF.Infrastructure.Config, EF.Infrastructure.Composition, EF.Infrastructure.Database,
  EF.Infrastructure.Database.Driver, EF.Infrastructure.Http, EF.Infrastructure.OutboxThread,
  EF.Infrastructure.UnitOfWork,
  EF.Presentation.Login, EF.Presentation.Main, EF.Shared.Logging;

function ConfigPath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'enterpriseflow.ini';
  if not FileExists(Result) then
    Result := 'config' + PathDelim + 'enterpriseflow.ini';
end;

procedure RunApplication;
var
  LConfig: TAppConfig;
  LSession: IDbSession;
  LClock: IClock;
  LLog: ILogger;
  LAuth: TAuthService;
  LContext: TUserContext;
  LLogged: Boolean;
  LServices: TAppServices;
  LWorker: TOutboxThread;
  LMain: TMainForm;
begin
  try
    LConfig := LoadConfig(ConfigPath);
    LSession := OpenSession(LConfig.Db);
  except
    on E: Exception do
    begin
      MessageDlg('Não foi possível conectar ao banco.' + sLineBreak + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;

  LClock := TSystemClock.Create;
  LLog := TJsonFileLogger.Create(LConfig.LogPath);
  LAuth := TAuthService.Create(NewAuthUow(LSession), LClock);
  try
    LLogged := TLoginForm.Execute(LAuth, LContext);
  finally
    LAuth.Free;
  end;
  if not LLogged then
    Exit;

  LServices := TAppServices.Create(LSession, LContext, LClock, LLog);
  LWorker := TOutboxThread.Create(LConfig, LContext);
  try
    Application.CreateForm(TMainForm, LMain);
    LMain.Setup(LServices, LLog, LWorker);
    Application.Run;
  finally
    LWorker.Shutdown;
    LServices.Free;
  end;
end;

end.
