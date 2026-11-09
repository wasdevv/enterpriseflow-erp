unit EF.Infrastructure.Database.Migrator;

{$I EF.inc}

interface

uses
  SysUtils, Classes,
  EF.Infrastructure.Database;

type
  TStatementList = array of string;

  EMigrationError = class(Exception);

  TMigrator = class
  private
    FSession: IDbSession;
    FLog: TStrings;
    procedure EnsureHistoryTable;
    procedure Note(const AText: string);
    function AppliedChecksum(const AVersion: string; out AChecksum: string): Boolean;
    procedure RunStatements(const AScript: string);
  public
    constructor Create(const ASession: IDbSession; const ALog: TStrings = nil);
    { Aplica em ordem o que falta. Recusa se um arquivo já aplicado foi editado. }
    function Migrate(const ADirectory: string): Integer;
    { Executa os scripts como estão. Para dados de demonstração, sem histórico. }
    procedure RunFile(const APath: string);
  end;

{ Separa um script no formato do isql: respeita strings, comentários e SET TERM. }
function SplitSqlScript(const AScript: string): TStatementList;

implementation

uses
  EF.Shared.Crypto;

function ReadUtf8File(const APath: string): string;
var
  LLines: TStringList;
begin
  LLines := TStringList.Create;
  try
    {$IFDEF FPC}
    LLines.LoadFromFile(APath);
    {$ELSE}
    LLines.LoadFromFile(APath, TEncoding.UTF8);
    {$ENDIF}
    Result := LLines.Text;
  finally
    LLines.Free;
  end;
end;

function SplitSqlScript(const AScript: string): TStatementList;
var
  LTerminator, LCurrent: string;
  LIndex, LLength: Integer;
  LStatements: TStatementList;

  procedure FlushStatement;
  var
    LText, LUpper: string;
  begin
    LText := Trim(LCurrent);
    LCurrent := '';
    if LText = '' then
      Exit;
    LUpper := UpperCase(LText);
    if Pos('SET TERM', LUpper) = 1 then
    begin
      LTerminator := Trim(Copy(LText, 9, MaxInt));
      Exit;
    end;
    SetLength(LStatements, Length(LStatements) + 1);
    LStatements[High(LStatements)] := LText;
  end;

begin
  SetLength(LStatements, 0);
  LTerminator := ';';
  LCurrent := '';
  LIndex := 1;
  LLength := Length(AScript);
  while LIndex <= LLength do
  begin
    if AScript[LIndex] = '''' then
    begin
      repeat
        LCurrent := LCurrent + AScript[LIndex];
        Inc(LIndex);
      until (LIndex > LLength) or (AScript[LIndex] = '''');
      if LIndex <= LLength then
      begin
        LCurrent := LCurrent + AScript[LIndex];
        Inc(LIndex);
      end;
    end
    else if Copy(AScript, LIndex, 2) = '--' then
    begin
      while (LIndex <= LLength) and not CharInSet(AScript[LIndex], [#10, #13]) do
        Inc(LIndex);
    end
    else if Copy(AScript, LIndex, 2) = '/*' then
    begin
      Inc(LIndex, 2);
      while (LIndex <= LLength) and (Copy(AScript, LIndex, 2) <> '*/') do
        Inc(LIndex);
      Inc(LIndex, 2);
    end
    else if Copy(AScript, LIndex, Length(LTerminator)) = LTerminator then
    begin
      Inc(LIndex, Length(LTerminator));
      FlushStatement;
    end
    else
    begin
      LCurrent := LCurrent + AScript[LIndex];
      Inc(LIndex);
    end;
  end;
  FlushStatement;
  Result := LStatements;
end;

constructor TMigrator.Create(const ASession: IDbSession; const ALog: TStrings);
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
end;

procedure TMigrator.Note(const AText: string);
begin
  if FLog <> nil then
    FLog.Add(AText);
end;

procedure TMigrator.EnsureHistoryTable;
var
  LExists: Boolean;
begin
  FSession.StartTransaction;
  try
    LExists := not FSession.Query('SELECT 1 AS x FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = ''SCHEMA_MIGRATIONS''').Eof;
    if not LExists then
      FSession.Execute('CREATE TABLE schema_migrations (version VARCHAR(100) NOT NULL PRIMARY KEY, checksum VARCHAR(64) NOT NULL, applied_at TIMESTAMP DEFAULT LOCALTIMESTAMP NOT NULL)');
    FSession.Commit;
  except
    FSession.Rollback;
    raise;
  end;
end;

function TMigrator.AppliedChecksum(const AVersion: string; out AChecksum: string): Boolean;
var
  LReader: IDbReader;
begin
  FSession.StartTransaction;
  try
    LReader := FSession.Query('SELECT checksum FROM schema_migrations WHERE version = :version', [P('version', AVersion)]);
    Result := not LReader.Eof;
    if Result then
      AChecksum := LReader.Str('checksum');
    LReader := nil;
    FSession.Commit;
  except
    FSession.Rollback;
    raise;
  end;
end;

procedure TMigrator.RunStatements(const AScript: string);
var
  LStatements: TStatementList;
  LIndex: Integer;
begin
  LStatements := SplitSqlScript(AScript);
  for LIndex := 0 to High(LStatements) do
  begin
    { DDL em Firebird só vale após commit: o próximo comando pode depender deste. }
    FSession.StartTransaction;
    try
      FSession.Execute(LStatements[LIndex]);
      FSession.Commit;
    except
      on E: Exception do
      begin
        FSession.Rollback;
        raise EMigrationError.CreateFmt('Falha no comando %d: %s'#10'%s', [LIndex + 1, E.Message, LStatements[LIndex]]);
      end;
    end;
  end;
end;

function TMigrator.Migrate(const ADirectory: string): Integer;
var
  LFiles: TStringList;
  LSearch: TSearchRec;
  LIndex: Integer;
  LVersion, LScript, LChecksum, LApplied: string;
begin
  Result := 0;
  EnsureHistoryTable;
  LFiles := TStringList.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(ADirectory) + '*.sql', faAnyFile, LSearch) = 0 then
    begin
      repeat
        LFiles.Add(LSearch.Name);
      until FindNext(LSearch) <> 0;
      FindClose(LSearch);
    end;
    if LFiles.Count = 0 then
      raise EMigrationError.CreateFmt('Nenhuma migration encontrada em %s', [ADirectory]);
    LFiles.Sort;

    for LIndex := 0 to LFiles.Count - 1 do
    begin
      LVersion := LFiles[LIndex];
      LScript := ReadUtf8File(IncludeTrailingPathDelimiter(ADirectory) + LVersion);
      { Fins de linha são normalizados: checkout Windows e Linux têm o mesmo checksum. }
      LChecksum := Sha256Hex(UTF8Encode(StringReplace(LScript, #13#10, #10, [rfReplaceAll])));
      if AppliedChecksum(LVersion, LApplied) then
      begin
        if LApplied <> LChecksum then
          raise EMigrationError.CreateFmt('Migration %s já aplicada foi alterada. Crie uma nova em vez de editar.', [LVersion]);
        Continue;
      end;
      RunStatements(LScript);
      FSession.StartTransaction;
      try
        FSession.Execute('INSERT INTO schema_migrations (version, checksum) VALUES (:version, :checksum)', [P('version', LVersion), P('checksum', LChecksum)]);
        FSession.Commit;
      except
        FSession.Rollback;
        raise;
      end;
      Note('aplicada: ' + LVersion);
      Inc(Result);
    end;
  finally
    LFiles.Free;
  end;
end;

procedure TMigrator.RunFile(const APath: string);
begin
  RunStatements(ReadUtf8File(APath));
  Note('executado: ' + ExtractFileName(APath));
end;

end.
