unit DUnitX.TestFramework;

{ NÃO É O DUNITX. Só as assinaturas usadas pelo programa de testes no ramo Delphi. }

interface

uses
  SysUtils, Classes;

type
  ITestLogger = interface
  end;

  IRunResults = interface
    function AllPassed: Boolean;
  end;

  ITestRunner = interface
    procedure SetUseRTTI(const AValue: Boolean);
    function GetUseRTTI: Boolean;
    procedure AddLogger(const ALogger: ITestLogger);
    function Execute: IRunResults;
    property UseRTTI: Boolean read GetUseRTTI write SetUseRTTI;
  end;

  TDUnitXOptions = class
  public
    XMLOutputFile: string;
  end;

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
    class function Options: TDUnitXOptions; static;
    class procedure RegisterTestFixture(const AClass: TClass; const AName: string = ''); static;
    class procedure CheckCommandLine; static;
    class function CreateRunner: ITestRunner; static;
  end;

implementation

class procedure Assert.Pass(const AMessage: string);
begin
end;

class procedure Assert.Fail(const AMessage: string);
begin
end;

class procedure Assert.IsTrue(const ACondition: Boolean; const AMessage: string);
begin
end;

class procedure Assert.IsFalse(const ACondition: Boolean; const AMessage: string);
begin
end;

class procedure Assert.AreEqual(const AExpected, AActual: string; const AMessage: string);
begin
end;

class procedure Assert.AreEqual(const AExpected, AActual: Integer; const AMessage: string);
begin
end;

class function TDUnitX.Options: TDUnitXOptions;
begin
  Result := nil;
end;

class procedure TDUnitX.RegisterTestFixture(const AClass: TClass; const AName: string);
begin
end;

class procedure TDUnitX.CheckCommandLine;
begin
end;

class function TDUnitX.CreateRunner: ITestRunner;
begin
  Result := nil;
end;

end.
