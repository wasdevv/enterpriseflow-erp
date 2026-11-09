program BootSmoke;

{ Sobe o programa pelo mesmo caminho do executável final: RunApplication, com configuração no
  ini ou no ambiente, janela de login, Application.Run e fechamento. }

{$I EF.inc}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Interfaces, Forms, Controls, ExtCtrls, ComCtrls, SysUtils, Classes,
  EF.Presentation.Bootstrap, EF.Presentation.Login, EF.Presentation.Main;

type
  TDriver = class
  public
    Started: QWord;
    LoggedIn, Closing: Boolean;
    procedure Tick(Sender: TObject);
  end;

procedure Fail(const AWhat: string);
begin
  WriteLn('  FAIL ', AWhat);
  Flush(Output);
  Halt(1);
end;

procedure TDriver.Tick(Sender: TObject);
var
  LIndex: Integer;
  LLogin: TLoginForm;
  LMain: TMainForm;
begin
  if GetTickCount64 - Started > 60000 then
    Fail('Tempo esgotado: a janela esperada não apareceu');
  if not LoggedIn then
  begin
    for LIndex := 0 to Screen.CustomFormCount - 1 do
      if Screen.CustomForms[LIndex] is TLoginForm then
      begin
        LLogin := TLoginForm(Screen.CustomForms[LIndex]);
        if not LLogin.Visible then
          Exit;
        WriteLn('  ok   Janela de login aberta a partir da configuração');
        LLogin.edtUser.Text := 'admin';
        LLogin.edtPassword.Text := 'demo1234';
        LoggedIn := True;
        LLogin.btnLogin.Click;
        Exit;
      end;
    Exit;
  end;
  if Closing or not (Application.MainForm is TMainForm) then
    Exit;
  LMain := TMainForm(Application.MainForm);
  if not LMain.Visible then
    Exit;
  Closing := True;
  if LMain.pcModules.PageCount <> 7 then
    Fail('Janela principal sem as 7 abas');
  WriteLn('  ok   Janela principal aberta com ', LMain.pcModules.PageCount, ' abas');
  Flush(Output);
  LMain.Close;
end;

var
  GDriver: TDriver;
  GTimer: TTimer;
begin
  Application.Scaled := False;
  Application.Initialize;
  GDriver := TDriver.Create;
  GDriver.Started := GetTickCount64;
  GTimer := TTimer.Create(nil);
  GTimer.Interval := 100;
  GTimer.OnTimer := GDriver.Tick;
  GTimer.Enabled := True;
  RunApplication;
  GTimer.Enabled := False;
  if not GDriver.Closing then
    Fail('RunApplication terminou antes do login');
  WriteLn('  ok   Programa encerrado sem erro, com o worker parado');
  Flush(Output);
  Halt(0);
end.
