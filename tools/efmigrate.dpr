program efmigrate;

{ efmigrate create|migrate|seed <arquivo.sql>. Configuração em EF_DB_* ou no ini. }

{$APPTYPE CONSOLE}
{$I EF.inc}

uses
  {$IFDEF FPC}{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}{$ENDIF}
  SysUtils, Classes,
  EF.Infrastructure.Config,
  EF.Infrastructure.Database,
  EF.Infrastructure.Database.Driver,
  EF.Infrastructure.Database.Migrator;

procedure Run;
var
  LCommand: string;
  LDb: TDbConfig;
  LMigrator: TMigrator;
  LLog: TStringList;
  LRoot: string;
begin
  LCommand := ParamStr(1);
  if not DbConfigFromEnvironment('EF_DB', LDb) then
    LDb := LoadConfig('config/enterpriseflow.ini').Db;
  LRoot := GetEnvironmentVariable('EF_MIGRATIONS_DIR');
  if LRoot = '' then
    LRoot := 'database/migrations';

  if LCommand = 'create' then
  begin
    CreateDatabase(LDb);
    WriteLn('banco criado: ', LDb.Database);
    Exit;
  end;

  LLog := TStringList.Create;
  try
    LMigrator := TMigrator.Create(OpenSession(LDb), LLog);
    try
      if LCommand = 'migrate' then
        WriteLn(LMigrator.Migrate(LRoot), ' migration(s) aplicada(s)')
      else if (LCommand = 'seed') and (ParamStr(2) <> '') then
        LMigrator.RunFile(ParamStr(2))
      else
        raise Exception.Create('Uso: efmigrate create | migrate | seed <arquivo.sql>');
    finally
      LMigrator.Free;
    end;
    Write(LLog.Text);
  finally
    LLog.Free;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
