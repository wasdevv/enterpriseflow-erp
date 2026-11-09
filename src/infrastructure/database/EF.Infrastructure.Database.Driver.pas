unit EF.Infrastructure.Database.Driver;

{ Único ponto que escolhe o adaptador por compilador. O resto do código só vê IDbSession. }

{$I EF.inc}

interface

uses
  EF.Infrastructure.Database;

function OpenSession(const AConfig: TDbConfig): IDbSession;
procedure CreateDatabase(const AConfig: TDbConfig);

implementation

uses
  {$IFDEF FPC}
  EF.Infrastructure.Database.SqlDb;
  {$ELSE}
  EF.Infrastructure.Database.FireDAC;
  {$ENDIF}

function OpenSession(const AConfig: TDbConfig): IDbSession;
begin
  Result := OpenFirebirdSession(AConfig);
end;

procedure CreateDatabase(const AConfig: TDbConfig);
begin
  CreateFirebirdDatabase(AConfig);
end;

end.
