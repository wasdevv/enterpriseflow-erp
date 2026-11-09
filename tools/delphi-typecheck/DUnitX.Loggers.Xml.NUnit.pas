unit DUnitX.Loggers.Xml.NUnit;

interface

uses
  DUnitX.TestFramework;

type
  TDUnitXXMLNUnitFileLogger = class(TInterfacedObject, ITestLogger)
  public
    constructor Create(const AFileName: string = '');
  end;

implementation

constructor TDUnitXXMLNUnitFileLogger.Create(const AFileName: string);
begin
  inherited Create;
end;

end.
