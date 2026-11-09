unit DUnitX.Loggers.Console;

interface

uses
  DUnitX.TestFramework;

type
  TDUnitXConsoleLogger = class(TInterfacedObject, ITestLogger)
  public
    constructor Create(const AQuiet: Boolean = False);
  end;

implementation

constructor TDUnitXConsoleLogger.Create(const AQuiet: Boolean);
begin
  inherited Create;
end;

end.
