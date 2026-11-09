unit EF.Presentation.Login;

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls,
  EF.Application.Ports, EF.Application.Catalog;

type
  TLoginForm = class(TForm)
    lblTitle: TLabel;
    lblSubtitle: TLabel;
    lblUser: TLabel;
    edtUser: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblError: TLabel;
    btnLogin: TButton;
    btnCancel: TButton;
    procedure btnLoginClick(Sender: TObject);
  private
    FAuth: TAuthService;
    FContext: TUserContext;
  public
    class function Execute(const AAuth: TAuthService; out AContext: TUserContext): Boolean;
  end;

implementation

{$R *.dfm}

uses
  EF.Domain.Exceptions;

class function TLoginForm.Execute(const AAuth: TAuthService; out AContext: TUserContext): Boolean;
var
  LForm: TLoginForm;
begin
  LForm := TLoginForm.Create(nil);
  try
    LForm.FAuth := AAuth;
    LForm.lblError.Caption := '';
    Result := LForm.ShowModal = mrOk;
    if Result then
      AContext := LForm.FContext;
  finally
    LForm.Free;
  end;
end;

procedure TLoginForm.btnLoginClick(Sender: TObject);
begin
  try
    FContext := FAuth.Login(Trim(edtUser.Text), edtPassword.Text);
    ModalResult := mrOk;
  except
    on E: EAuthenticationFailed do
    begin
      lblError.Caption := E.Message;
      edtPassword.Text := '';
      edtPassword.SetFocus;
    end;
  end;
end;

end.
