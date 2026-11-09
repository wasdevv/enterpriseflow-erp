unit EF.Presentation.Main;

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, ComCtrls, Menus, Dialogs, ExtCtrls,
  EF.Application.Ports, EF.Infrastructure.Composition, EF.Infrastructure.OutboxThread,
  EF.Presentation.Common, EF.Shared.Logging;

type
  TMainForm = class(TForm)
    menuMain: TMainMenu;
    miFile: TMenuItem;
    miPassword: TMenuItem;
    miExit: TMenuItem;
    pcModules: TPageControl;
    sbStatus: TStatusBar;
    procedure miPasswordClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure pcModulesChange(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FApp: TAppServices;
    FLog: ILogger;
    FWorker: TOutboxThread;
    function AddModule(const ACaption: string; const AFrameClass: TComponentClass): TModuleFrame;
    procedure HandleException(Sender: TObject; E: Exception);
    procedure WakeWorker(Sender: TObject);
  public
    procedure Setup(const AApp: TAppServices; const ALog: ILogger; const AWorker: TOutboxThread);
  end;

implementation

{$R *.dfm}

uses
  EF.Domain.Exceptions, EF.Presentation.Fields,
  EF.Presentation.CatalogFrame, EF.Presentation.StockFrame, EF.Presentation.PurchasesFrame,
  EF.Presentation.SalesFrame, EF.Presentation.FinanceFrame, EF.Presentation.IntegrationFrame,
  EF.Presentation.ReportsFrame, EF.Shared.Text;

function TMainForm.AddModule(const ACaption: string; const AFrameClass: TComponentClass): TModuleFrame;
var
  LTab: TTabSheet;
begin
  LTab := TTabSheet.Create(pcModules);
  LTab.PageControl := pcModules;
  LTab.Caption := ACaption;
  Result := TModuleFrame(AFrameClass.Create(LTab));
  Result.Name := '';
  Result.Parent := LTab;
  Result.Align := alClient;
  Result.Bind(FApp);
end;

procedure TMainForm.Setup(const AApp: TAppServices; const ALog: ILogger; const AWorker: TOutboxThread);
var
  LIntegration: TIntegrationFrame;
begin
  FApp := AApp;
  FLog := ALog;
  FWorker := AWorker;
  Application.OnException := HandleException;
  AddModule('Vendas', TSalesFrame);
  AddModule('Estoque', TStockFrame);
  AddModule('Compras', TPurchasesFrame);
  if AApp.Context.Has(PermReceivableSettle) or AApp.Context.Has(PermReportsView) then
    AddModule('Financeiro', TFinanceFrame);
  AddModule('Cadastros', TCatalogFrame);
  if AApp.Context.Has(PermReportsView) then
    AddModule('Relatórios', TReportsFrame);
  if AApp.Context.Has(PermIntegrationManage) then
  begin
    LIntegration := TIntegrationFrame(AddModule('Integração', TIntegrationFrame));
    LIntegration.OnWakeWorker := WakeWorker;
  end;
  sbStatus.SimpleText := 'Usuário: ' + AApp.Context.Username + '   |   Distribuidora São Lucas (cenário fictício de portfólio)';
  pcModules.ActivePageIndex := 0;
  pcModulesChange(nil);
end;

procedure TMainForm.pcModulesChange(Sender: TObject);
var
  LTab: TTabSheet;
begin
  { Recarrega só a aba visível: nada de consulta para tela que ninguém está olhando. }
  LTab := pcModules.ActivePage;
  if (LTab <> nil) and (LTab.ControlCount > 0) and (LTab.Controls[0] is TModuleFrame) then
    TModuleFrame(LTab.Controls[0]).Reload;
end;

procedure TMainForm.WakeWorker(Sender: TObject);
begin
  if FWorker <> nil then
    FWorker.Wake;
end;

procedure TMainForm.HandleException(Sender: TObject; E: Exception);
var
  LCorrelation: string;
begin
  if E is EDomainError then
  begin
    ShowDomainMessage(E.Message);
    pcModulesChange(nil);
    Exit;
  end;
  { Erro inesperado: o detalhe vai para o log, e o usuário recebe a referência para o suporte. }
  LCorrelation := NewCorrelationId;
  if FLog <> nil then
    FLog.Log(llError, 'ui.unhandled_exception', LCorrelation, TJsonObjectBuilder.New.Str('class', E.ClassName).Str('message', E.Message).ToJson);
  MessageDlg('Ocorreu um erro inesperado. Referência: ' + LCorrelation, mtError, [mbOK], 0);
end;

procedure TMainForm.miPasswordClick(Sender: TObject);
var
  LDialog: TFieldsDialog;
begin
  LDialog := TFieldsDialog.CreateDialog(Self, 'Trocar senha');
  try
    LDialog.AddText('current', 'Senha atual', '', True);
    LDialog.AddText('new', 'Nova senha', '', True);
    while LDialog.Execute do
      try
        FApp.Auth.ChangePassword(FApp.Context, LDialog.Text('current'), LDialog.Text('new'));
        Break;
      except
        on E: EDomainError do
          ShowDomainMessage(E.Message);
      end;
  finally
    LDialog.Free;
  end;
end;

procedure TMainForm.miExitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  Application.OnException := nil;
end;

end.
