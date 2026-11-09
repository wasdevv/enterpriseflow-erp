program EnterpriseFlowLcl;

{ Só para verificação: compila as mesmas telas com a LCL (Lazarus), onde não há Delphi.
  O produto é EnterpriseFlow.dpr, em VCL. }

{$I EF.inc}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Interfaces, Forms,
  EF.Presentation.Bootstrap;

begin
  Application.Scaled := False;
  Application.Initialize;
  Application.Title := 'EnterpriseFlow ERP';
  RunApplication;
end.
