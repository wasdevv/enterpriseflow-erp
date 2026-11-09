program EnterpriseFlowTests;

{$APPTYPE CONSOLE}
{$I EF.inc}

uses
  {$IFDEF FPC}{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}{$ENDIF}
  SysUtils,
  {$IFNDEF FPC}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  {$ENDIF}
  DUnitX.TestFramework,
  EF.Tests.Money,
  EF.Tests.Domain,
  EF.Tests.Stock,
  EF.Tests.Sales,
  EF.Tests.Finance,
  EF.Tests.Integration,
  EF.Tests.Platform;

{$IFNDEF FPC}
var
  LRunner: ITestRunner;
  LResults: IRunResults;
{$ENDIF}
begin
  {$IFDEF FPC}
  Halt(RunRegisteredFixtures);
  {$ELSE}
  TDUnitX.CheckCommandLine;
  LRunner := TDUnitX.CreateRunner;
  LRunner.UseRTTI := False;
  LRunner.AddLogger(TDUnitXConsoleLogger.Create(True));
  LRunner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile));
  LResults := LRunner.Execute;
  if not LResults.AllPassed then
    System.ExitCode := 1;
  {$ENDIF}
end.
