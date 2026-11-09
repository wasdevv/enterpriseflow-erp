unit DUnitX.TestFramework;

{ Só para Free Pascal: expõe o subconjunto da API do DUnitX que os testes usam, para o
  mesmo código de teste rodar em CI sem licença de Delphi. Em Delphi este diretório fica
  fora do search path e os testes usam o DUnitX de verdade. }

{$MODE DELPHI}
{$H+}
{$M+}

interface

uses
  SysUtils, Classes;

type
  ETestFailure = class(Exception);

  Assert = class
  public
    class procedure Pass(const AMessage: string = ''); static;
    class procedure Fail(const AMessage: string = ''); static;
    class procedure IsTrue(const ACondition: Boolean; const AMessage: string = ''); static;
    class procedure IsFalse(const ACondition: Boolean; const AMessage: string = ''); static;
    class procedure AreEqual(const AExpected, AActual: string; const AMessage: string = ''); overload; static;
    class procedure AreEqual(const AExpected, AActual: Integer; const AMessage: string = ''); overload; static;
  end;

  TDUnitX = class
  public
    class procedure RegisterTestFixture(const AClass: TClass; const AName: string = ''); static;
  end;

{ Roda as fixtures registradas e devolve o exit code. --filter=texto restringe. }
function RunRegisteredFixtures: Integer;

implementation

uses
  testutils;

type
  TTestMethod = procedure of object;

var
  GFixtures: array of TClass;

class procedure Assert.Pass(const AMessage: string);
begin
end;

class procedure Assert.Fail(const AMessage: string);
begin
  raise ETestFailure.Create(AMessage);
end;

class procedure Assert.IsTrue(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise ETestFailure.Create('Esperado verdadeiro. ' + AMessage);
end;

class procedure Assert.IsFalse(const ACondition: Boolean; const AMessage: string);
begin
  if ACondition then
    raise ETestFailure.Create('Esperado falso. ' + AMessage);
end;

class procedure Assert.AreEqual(const AExpected, AActual: string; const AMessage: string);
begin
  if AExpected <> AActual then
    raise ETestFailure.CreateFmt('Esperado "%s", obtido "%s". %s', [AExpected, AActual, AMessage]);
end;

class procedure Assert.AreEqual(const AExpected, AActual: Integer; const AMessage: string);
begin
  if AExpected <> AActual then
    raise ETestFailure.CreateFmt('Esperado %d, obtido %d. %s', [AExpected, AActual, AMessage]);
end;

class procedure TDUnitX.RegisterTestFixture(const AClass: TClass; const AName: string);
begin
  SetLength(GFixtures, Length(GFixtures) + 1);
  GFixtures[High(GFixtures)] := AClass;
end;

procedure CallIfPresent(const AFixture: TObject; const AName: string);
var
  LMethod: TMethod;
begin
  LMethod.Code := AFixture.MethodAddress(AName);
  LMethod.Data := AFixture;
  if LMethod.Code <> nil then
    TTestMethod(LMethod)();
end;

function RunRegisteredFixtures: Integer;
var
  LFixtureIndex, LMethodIndex, LArg, LPassed, LFailed: Integer;
  LFixture: TObject;
  LMethods: TStringList;
  LMethodName, LTestName, LFilter: string;
  LMethod: TMethod;
  LStart: QWord;
begin
  LFilter := '';
  for LArg := 1 to ParamCount do
    if Pos('--filter=', ParamStr(LArg)) = 1 then
      LFilter := LowerCase(Copy(ParamStr(LArg), 10, MaxInt));

  LPassed := 0;
  LFailed := 0;
  for LFixtureIndex := 0 to High(GFixtures) do
  begin
    LFixture := GFixtures[LFixtureIndex].Create;
    LMethods := TStringList.Create;
    try
      GetMethodList(LFixture, LMethods);
      for LMethodIndex := 0 to LMethods.Count - 1 do
      begin
        LMethodName := LMethods[LMethodIndex];
        if SameText(LMethodName, 'SetUp') or SameText(LMethodName, 'TearDown') then
          Continue;
        LTestName := LFixture.ClassName + '.' + LMethodName;
        if (LFilter <> '') and (Pos(LFilter, LowerCase(LTestName)) = 0) then
          Continue;
        LStart := GetTickCount64;
        try
          CallIfPresent(LFixture, 'SetUp');
          try
            LMethod.Code := LFixture.MethodAddress(LMethodName);
            LMethod.Data := LFixture;
            TTestMethod(LMethod)();
          finally
            CallIfPresent(LFixture, 'TearDown');
          end;
          Inc(LPassed);
          WriteLn(Format('  ok   %s (%d ms)', [LTestName, GetTickCount64 - LStart]));
        except
          on E: Exception do
          begin
            Inc(LFailed);
            WriteLn(Format('  FAIL %s: [%s] %s', [LTestName, E.ClassName, E.Message]));
          end;
        end;
      end;
    finally
      LMethods.Free;
      LFixture.Free;
    end;
  end;
  WriteLn(Format('%d passaram, %d falharam', [LPassed, LFailed]));
  if LFailed > 0 then
    Result := 1
  else
    Result := 0;
end;

end.
