unit EF.Infrastructure.Config;

{$I EF.inc}

interface

uses
  SysUtils, IniFiles,
  EF.Infrastructure.Database;

type
  TAppConfig = record
    Db: TDbConfig;
    ApiBaseUrl: string;
    ApiTimeoutMs: Integer;
    LogPath: string;
  end;

{ Ordem: variável de ambiente EF_*, depois arquivo ini. Senha nunca tem valor padrão. }
function LoadConfig(const AIniPath: string): TAppConfig;
function DbConfigFromEnvironment(const APrefix: string; out AConfig: TDbConfig): Boolean;

implementation

function Setting(const AIni: TIniFile; const AEnv, ASection, AKey, ADefault: string): string;
begin
  Result := GetEnvironmentVariable(AEnv);
  if Result = '' then
    if AIni <> nil then
      Result := AIni.ReadString(ASection, AKey, ADefault)
    else
      Result := ADefault;
end;

function LoadConfig(const AIniPath: string): TAppConfig;
var
  LIni: TIniFile;
begin
  LIni := nil;
  if FileExists(AIniPath) then
    LIni := TIniFile.Create(AIniPath);
  try
    Result.Db.Host := Setting(LIni, 'EF_DB_HOST', 'database', 'host', '127.0.0.1');
    Result.Db.Port := StrToIntDef(Setting(LIni, 'EF_DB_PORT', 'database', 'port', '3050'), 3050);
    Result.Db.Database := Setting(LIni, 'EF_DB_PATH', 'database', 'path', '');
    Result.Db.User := Setting(LIni, 'EF_DB_USER', 'database', 'user', 'SYSDBA');
    Result.Db.Password := Setting(LIni, 'EF_DB_PASSWORD', 'database', 'password', '');
    Result.ApiBaseUrl := Setting(LIni, 'EF_API_URL', 'integration', 'base_url', 'http://127.0.0.1:8765');
    Result.ApiTimeoutMs := StrToIntDef(Setting(LIni, 'EF_API_TIMEOUT_MS', 'integration', 'timeout_ms', '5000'), 5000);
    Result.LogPath := Setting(LIni, 'EF_LOG_PATH', 'logging', 'path', 'enterpriseflow.log');
  finally
    LIni.Free;
  end;
  if (Result.Db.Database = '') or (Result.Db.Password = '') then
    raise Exception.Create('Configure o banco: copie config/enterpriseflow.ini.example para config/enterpriseflow.ini ou defina EF_DB_PATH e EF_DB_PASSWORD.');
end;

function DbConfigFromEnvironment(const APrefix: string; out AConfig: TDbConfig): Boolean;
begin
  AConfig.Host := GetEnvironmentVariable(APrefix + '_HOST');
  AConfig.Port := StrToIntDef(GetEnvironmentVariable(APrefix + '_PORT'), 3050);
  AConfig.Database := GetEnvironmentVariable(APrefix + '_PATH');
  AConfig.User := GetEnvironmentVariable(APrefix + '_USER');
  AConfig.Password := GetEnvironmentVariable(APrefix + '_PASSWORD');
  if AConfig.Host = '' then
    AConfig.Host := '127.0.0.1';
  if AConfig.User = '' then
    AConfig.User := 'SYSDBA';
  Result := (AConfig.Database <> '') and (AConfig.Password <> '');
end;

end.
