unit EF.Presentation.Fields;

{ Diálogo de campos montado em tempo de execução: evita um formulário por cadastro. A
  validação fica no serviço, e a tela só mostra a mensagem e mantém o diálogo aberto. }

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls,
  EF.Application.Ports;

type
  TFieldsDialog = class(TForm)
    pnlButtons: TPanel;
    btnOk: TButton;
    btnCancel: TButton;
    pnlFields: TPanel;
    procedure FormDestroy(Sender: TObject);
  private
    FKeys: TStringList;
    FNextTop: Integer;
    function AddCaption(const ACaption: string): Integer;
    function ControlOf(const AKey: string): TControl;
    procedure Place(const AKey: string; const AControl: TWinControl; const ATop: Integer);
  public
    constructor CreateDialog(const AOwner: TComponent; const ATitle: string);
    procedure AddText(const AKey, ACaption, AValue: string; const APassword: Boolean = False);
    procedure AddCheck(const AKey, ACaption: string; const AChecked: Boolean);
    procedure AddCombo(const AKey, ACaption: string; const ATable: TDataTable; const AIdColumn, ATextColumn: string; const ASelectedId: Int64 = 0; const AAddEmpty: Boolean = False);
    function Text(const AKey: string): string;
    procedure SetText(const AKey, AValue: string);
    procedure SelectIndex(const AKey: string; const AIndex: Integer);
    function Checked(const AKey: string): Boolean;
    function SelectedId(const AKey: string): Int64;
    function SelectedText(const AKey: string): string;
    function Execute: Boolean;
  end;

implementation

{$R *.dfm}

uses
  EF.Presentation.Common;

constructor TFieldsDialog.CreateDialog(const AOwner: TComponent; const ATitle: string);
begin
  inherited Create(AOwner);
  Caption := ATitle;
  FKeys := TStringList.Create;
  FNextTop := 12;
end;

procedure TFieldsDialog.FormDestroy(Sender: TObject);
begin
  FKeys.Free;
end;

function TFieldsDialog.AddCaption(const ACaption: string): Integer;
var
  LLabel: TLabel;
begin
  LLabel := TLabel.Create(Self);
  LLabel.Parent := pnlFields;
  LLabel.Left := 12;
  LLabel.Top := FNextTop + 4;
  LLabel.Caption := ACaption;
  Result := FNextTop;
  Inc(FNextTop, 32);
end;

procedure TFieldsDialog.Place(const AKey: string; const AControl: TWinControl; const ATop: Integer);
begin
  AControl.Parent := pnlFields;
  AControl.Left := 240;
  AControl.Top := ATop;
  AControl.Width := 300;
  FKeys.AddObject(AKey, AControl);
end;

procedure TFieldsDialog.AddText(const AKey, ACaption, AValue: string; const APassword: Boolean);
var
  LEdit: TEdit;
begin
  LEdit := TEdit.Create(Self);
  Place(AKey, LEdit, AddCaption(ACaption));
  LEdit.Text := AValue;
  if APassword then
    LEdit.PasswordChar := '*';
end;

procedure TFieldsDialog.AddCheck(const AKey, ACaption: string; const AChecked: Boolean);
var
  LCheck: TCheckBox;
begin
  LCheck := TCheckBox.Create(Self);
  Place(AKey, LCheck, AddCaption(ACaption));
  LCheck.Checked := AChecked;
  LCheck.Caption := '';
end;

procedure TFieldsDialog.AddCombo(const AKey, ACaption: string; const ATable: TDataTable; const AIdColumn, ATextColumn: string; const ASelectedId: Int64; const AAddEmpty: Boolean);
var
  LCombo: TComboBox;
begin
  LCombo := TComboBox.Create(Self);
  Place(AKey, LCombo, AddCaption(ACaption));
  LCombo.Style := csDropDownList;
  FillCombo(LCombo, ATable, AIdColumn, ATextColumn, AAddEmpty);
  SelectComboId(LCombo, ASelectedId);
end;

function TFieldsDialog.ControlOf(const AKey: string): TControl;
var
  LIndex: Integer;
begin
  LIndex := FKeys.IndexOf(AKey);
  if LIndex < 0 then
    raise Exception.CreateFmt('Campo inexistente: %s', [AKey]);
  Result := TControl(FKeys.Objects[LIndex]);
end;

function TFieldsDialog.Text(const AKey: string): string;
begin
  Result := Trim(TEdit(ControlOf(AKey)).Text);
end;

procedure TFieldsDialog.SetText(const AKey, AValue: string);
begin
  TEdit(ControlOf(AKey)).Text := AValue;
end;

procedure TFieldsDialog.SelectIndex(const AKey: string; const AIndex: Integer);
begin
  TComboBox(ControlOf(AKey)).ItemIndex := AIndex;
end;

function TFieldsDialog.Checked(const AKey: string): Boolean;
begin
  Result := TCheckBox(ControlOf(AKey)).Checked;
end;

function TFieldsDialog.SelectedId(const AKey: string): Int64;
begin
  Result := ComboId(TComboBox(ControlOf(AKey)));
end;

function TFieldsDialog.SelectedText(const AKey: string): string;
begin
  Result := TComboBox(ControlOf(AKey)).Text;
end;

function TFieldsDialog.Execute: Boolean;
begin
  ClientHeight := FNextTop + pnlButtons.Height + 12;
  Result := ShowModal = mrOk;
end;

end.
