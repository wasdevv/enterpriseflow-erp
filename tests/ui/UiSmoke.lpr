program UiSmoke;

{ Dirige as telas de verdade, com banco e serviço simulado reais: abre diálogos, preenche campos
  e clica nos botões. Roda com a LCL em Xvfb. Prova DFMs, eventos e o fluxo ponta a ponta, mas é
  a LCL, não a VCL: não substitui compilar e abrir no Delphi (docs/verificacao-delphi.md). }

{$I EF.inc}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  Interfaces, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Grids, Graphics, LCLIntf, LCLType,
  SysUtils, Classes,
  EF.Application.Ports, EF.Application.Catalog,
  EF.Infrastructure.Config, EF.Infrastructure.Composition, EF.Infrastructure.Database,
  EF.Infrastructure.Database.Driver, EF.Infrastructure.OutboxThread, EF.Infrastructure.UnitOfWork,
  EF.Presentation.Common, EF.Presentation.Fields, EF.Presentation.Lines, EF.Presentation.Login,
  EF.Presentation.Main, EF.Presentation.CatalogFrame, EF.Presentation.StockFrame,
  EF.Presentation.PurchasesFrame, EF.Presentation.SalesFrame, EF.Presentation.FinanceFrame,
  EF.Presentation.IntegrationFrame, EF.Presentation.ReportsFrame, EF.Shared.Logging;

type
  TDialogAction = procedure(const AForm: TCustomForm) of object;

  TSmoke = class
  private
    FActions: array of TDialogAction;
    FNextAction: Integer;
    FTimer: TTimer;
    FBusy: Boolean;
    FFailures, FChecks: Integer;
    FLastMessage: string;
    FAuth: TAuthService;
    FServices: TAppServices;
    FMain: TMainForm;
    FWorker: TOutboxThread;
    FShots: string;
    FModalSince: QWord;
    procedure Pump(Sender: TObject);
    procedure Queue(const AAction: TDialogAction);
    procedure Check(const ACondition: Boolean; const AWhat: string);
    procedure Press(const AButton: TButton);
    procedure Sink(const AMessage: string);
    procedure Shot(const AName: string);
    procedure Settle;
    function Frame(const ACaption: string): TModuleFrame;
    procedure OpenTab(const ACaption: string);
    { Respostas às janelas modais, na ordem em que aparecem. }
    procedure LoginWrong(const AForm: TCustomForm);
    procedure LoginRight(const AForm: TCustomForm);
    procedure FillSaleOrder(const AForm: TCustomForm);
    procedure AcceptDialog(const AForm: TCustomForm);
    procedure FillCancelReason(const AForm: TCustomForm);
    procedure FillPartialSettlement(const AForm: TCustomForm);
    procedure FillReverseReason(const AForm: TCustomForm);
    procedure FillTransfer(const AForm: TCustomForm);
    procedure FillTransferDestination(const AForm: TCustomForm);
    procedure FillAdjustment(const AForm: TCustomForm);
    procedure FillPurchaseOrder(const AForm: TCustomForm);
    procedure FillReceipt(const AForm: TCustomForm);
    procedure FillInvalidCustomer(const AForm: TCustomForm);
    procedure FillValidCustomer(const AForm: TCustomForm);
    procedure ScenarioLogin;
    procedure ScenarioSales;
    procedure ScenarioFinance;
    procedure ScenarioStock;
    procedure ScenarioPurchases;
    procedure ScenarioCatalog;
    procedure ScenarioReports;
    procedure ScenarioIntegration;
  public
    function Run: Integer;
  end;

procedure TSmoke.Queue(const AAction: TDialogAction);
begin
  SetLength(FActions, Length(FActions) + 1);
  FActions[High(FActions)] := AAction;
end;

procedure TSmoke.Pump(Sender: TObject);
var
  LIndex: Integer;
  LForm: TCustomForm;
begin
  if FBusy then
    Exit;
  LForm := nil;
  for LIndex := 0 to Screen.CustomFormCount - 1 do
    if (fsModal in Screen.CustomForms[LIndex].FormState) and Screen.CustomForms[LIndex].Visible then
    begin
      LForm := Screen.CustomForms[LIndex];
      Break;
    end;
  if LForm = nil then
  begin
    FModalSince := 0;
    Exit;
  end;
  { Já recebeu resultado e está fechando: a próxima ação é para a próxima abertura. }
  if LForm.ModalResult <> mrNone then
    Exit;
  if FNextAction > High(FActions) then
  begin
    { Janela que o roteiro não esperava: falha e fecha, em vez de travar a execução. }
    if FModalSince = 0 then
      FModalSince := GetTickCount64
    else if GetTickCount64 - FModalSince > 3000 then
    begin
      Check(False, 'Janela modal inesperada: ' + LForm.Caption + ' / última mensagem: ' + FLastMessage);
      LForm.ModalResult := mrCancel;
      FModalSince := 0;
    end;
    Exit;
  end;
  FModalSince := 0;
  FBusy := True;
  try
    Inc(FNextAction);
    FActions[FNextAction - 1](LForm);
  finally
    FBusy := False;
  end;
end;

procedure TSmoke.Check(const ACondition: Boolean; const AWhat: string);
begin
  Inc(FChecks);
  if ACondition then
    WriteLn('  ok   ', AWhat)
  else
  begin
    Inc(FFailures);
    WriteLn('  FAIL ', AWhat);
  end;
  Flush(Output);
end;

procedure TSmoke.Press(const AButton: TButton);
begin
  { Mesmo caminho de um clique: exceção vai para o Application.OnException da janela principal. }
  FLastMessage := '';
  try
    AButton.Click;
  except
    Application.HandleException(AButton);
  end;
  Settle;
end;

procedure TSmoke.Sink(const AMessage: string);
begin
  FLastMessage := AMessage;
  WriteLn('       mensagem: ', AMessage);
  Flush(Output);
end;

procedure TSmoke.Settle;
var
  LIndex: Integer;
begin
  for LIndex := 1 to 5 do
  begin
    Application.ProcessMessages;
    Sleep(15);
  end;
end;

procedure TSmoke.Shot(const AName: string);
var
  LBitmap: TBitmap;
  LPng: TPortableNetworkGraphic;
{$IFDEF MSWINDOWS}
  LIndex: Integer;
  LForm: TCustomForm;
{$ELSE}
  LDc: HDC;
{$ENDIF}
begin
  if FShots = '' then
    Exit;
  Settle;
  LPng := TPortableNetworkGraphic.Create;
  {$IFDEF MSWINDOWS}
  { Só a janela do programa: no Windows, capturar a tela pegaria o que a pessoa está fazendo. }
  LForm := FMain;
  for LIndex := 0 to Screen.CustomFormCount - 1 do
    if (fsModal in Screen.CustomForms[LIndex].FormState) and Screen.CustomForms[LIndex].Visible then
    begin
      LForm := Screen.CustomForms[LIndex];
      Break;
    end;
  if LForm = nil then
  begin
    LPng.Free;
    Exit;
  end;
  LBitmap := LForm.GetFormImage;
  {$ELSE}
  LBitmap := TBitmap.Create;
  LDc := GetDC(0);
  try
    LBitmap.LoadFromDevice(LDc);
  finally
    ReleaseDC(0, LDc);
  end;
  {$ENDIF}
  try
    LPng.Assign(LBitmap);
    LPng.SaveToFile(IncludeTrailingPathDelimiter(FShots) + AName + '.png');
  finally
    LPng.Free;
    LBitmap.Free;
  end;
end;

function TSmoke.Frame(const ACaption: string): TModuleFrame;
var
  LIndex: Integer;
begin
  for LIndex := 0 to FMain.pcModules.PageCount - 1 do
    if FMain.pcModules.Pages[LIndex].Caption = ACaption then
      Exit(TModuleFrame(FMain.pcModules.Pages[LIndex].Controls[0]));
  raise Exception.Create('Aba inexistente: ' + ACaption);
end;

procedure TSmoke.OpenTab(const ACaption: string);
var
  LIndex: Integer;
begin
  for LIndex := 0 to FMain.pcModules.PageCount - 1 do
    if FMain.pcModules.Pages[LIndex].Caption = ACaption then
      FMain.pcModules.ActivePageIndex := LIndex;
  FMain.pcModulesChange(nil);
  Settle;
end;

procedure TSmoke.LoginWrong(const AForm: TCustomForm);
var
  LForm: TLoginForm;
begin
  LForm := AForm as TLoginForm;
  Shot('01-login');
  LForm.edtUser.Text := 'admin';
  LForm.edtPassword.Text := 'senha-errada';
  LForm.btnLogin.Click;
  Check(LForm.lblError.Caption <> '', 'Senha errada mostra erro e mantém a janela aberta: ' + LForm.lblError.Caption);
  Check(LForm.ModalResult = mrNone, 'Senha errada não fecha a janela');
end;

procedure TSmoke.LoginRight(const AForm: TCustomForm);
var
  LForm: TLoginForm;
begin
  LForm := AForm as TLoginForm;
  LForm.edtPassword.Text := 'demo1234';
  LForm.btnLogin.Click;
end;

procedure TSmoke.ScenarioLogin;
var
  LContext: TUserContext;
begin
  Queue(LoginWrong);
  Queue(LoginRight);
  Check(TLoginForm.Execute(FAuth, LContext), 'Login com a senha certa');
  Check(LContext.Has(PermOrderConfirm), 'Permissões do perfil carregadas');
  FServices := TAppServices.Create(OpenSession(LoadConfig('').Db), LContext, TSystemClock.Create, TNullLogger.Create);
  FWorker := TOutboxThread.Create(LoadConfig(''), LContext, 300);
  Application.CreateForm(TMainForm, FMain);
  FMain.Show;
  FMain.Setup(FServices, TNullLogger.Create, FWorker);
  Settle;
  Check(FMain.pcModules.PageCount = 7, 'Administrador vê as 7 abas');
end;

procedure TSmoke.FillSaleOrder(const AForm: TCustomForm);
var
  LForm: TLinesForm;
begin
  LForm := AForm as TLinesForm;
  Check(LForm.cbParty.Items.Count >= 7, 'Clientes de demonstração no combo');
  LForm.edtSearch.Text := 'CAB-FLX-2.5';
  LForm.btnSearch.Click;
  Check(LForm.cbProduct.Items.Count = 1, 'Busca filtra o produto: ' + LForm.cbProduct.Text);
  LForm.edtQuantity.Text := '10,5';
  LForm.btnAdd.Click;
  Check(LForm.gridLines.Cells[3, 1] = '10,5', 'Item fracionado entra na grade');
  Shot('02-novo-pedido');
  LForm.btnPrimary.Click;
end;

procedure TSmoke.AcceptDialog(const AForm: TCustomForm);
begin
  (AForm as TFieldsDialog).btnOk.Click;
end;

procedure TSmoke.FillCancelReason(const AForm: TCustomForm);
begin
  (AForm as TFieldsDialog).SetText('value', 'Teste de cancelamento tardio');
  (AForm as TFieldsDialog).btnOk.Click;
end;

procedure TSmoke.ScenarioSales;
var
  LFrame: TSalesFrame;
  LOrder: string;
begin
  OpenTab('Vendas');
  LFrame := Frame('Vendas') as TSalesFrame;
  Queue(FillSaleOrder);
  Press(LFrame.btnNew);
  LFrame.Reload;
  LFrame.gridOrders.Row := 1;
  LOrder := GridCell(LFrame.gridOrders, 'Pedido');
  Check(GridCell(LFrame.gridOrders, 'Status') = 'RESERVED', 'Pedido novo fica reservado: ' + GridCell(LFrame.gridOrders, 'Status'));
  Check(GridCell(LFrame.gridOrders, 'Total') = 'R$ 39,90', 'Total 10,5 x R$ 3,80 calculado sem erro de arredondamento: ' + GridCell(LFrame.gridOrders, 'Total'));
  LFrame.gridOrdersClick(nil);
  Check(GridCell(LFrame.gridItems, 'Reserva') = 'ACTIVE', 'Item com reserva ativa');
  Shot('03-vendas');

  Press(LFrame.btnPick);
  LFrame.gridOrders.Row := 1;
  Check(GridCell(LFrame.gridOrders, 'Status') = 'PICKING', 'Separação iniciada');
  Queue(AcceptDialog);
  Press(LFrame.btnShip);
  LFrame.gridOrders.Row := 1;
  Check(GridCell(LFrame.gridOrders, 'Status') = 'SHIPPED', 'Pedido expedido');
  Queue(AcceptDialog);
  Press(LFrame.btnInvoice);
  LFrame.gridOrders.Row := 1;
  Check(GridCell(LFrame.gridOrders, 'Status') = 'INVOICED', 'Pedido faturado');
  LFrame.gridOrdersClick(nil);
  Check(GridCell(LFrame.gridItems, 'Reserva') = 'CONSUMED', 'Reserva virou baixa');
  LFrame.pcDetail.ActivePage := LFrame.tsHistory;
  Check(LFrame.gridHistory.RowCount = 7, 'Histórico tem as 6 mudanças de status');
  Shot('04-historico');
  LFrame.pcDetail.ActivePage := LFrame.tsItems;

  Queue(FillCancelReason);
  Press(LFrame.btnCancelOrder);
  Check(Pos('não pode passar', FLastMessage) > 0, 'Cancelar pedido faturado é recusado com mensagem clara');
end;

procedure TSmoke.FillPartialSettlement(const AForm: TCustomForm);
var
  LForm: TFieldsDialog;
begin
  LForm := AForm as TFieldsDialog;
  LForm.SetText('principal', '10,00');
  Shot('05-liquidar');
  LForm.btnOk.Click;
end;

procedure TSmoke.FillReverseReason(const AForm: TCustomForm);
begin
  (AForm as TFieldsDialog).SetText('value', 'Cheque devolvido');
  (AForm as TFieldsDialog).btnOk.Click;
end;

procedure TSmoke.ScenarioFinance;
var
  LFrame: TFinanceFrame;
begin
  OpenTab('Financeiro');
  LFrame := Frame('Financeiro') as TFinanceFrame;
  LFrame.gridInstallments.Row := 1;
  Check(GridCell(LFrame.gridInstallments, 'Em aberto') = 'R$ 39,90', 'Parcela em aberto no valor do pedido');
  Queue(FillPartialSettlement);
  Press(LFrame.btnSettle);
  LFrame.gridInstallments.Row := 1;
  Check(GridCell(LFrame.gridInstallments, 'Em aberto') = 'R$ 29,90', 'Liquidação parcial abate o saldo: ' + GridCell(LFrame.gridInstallments, 'Em aberto'));
  LFrame.gridInstallmentsClick(nil);
  LFrame.gridSettlements.Row := 1;
  Check(GridCell(LFrame.gridSettlements, 'Principal') = 'R$ 10,00', 'Liquidação na grade');
  Shot('06-financeiro');
  Queue(FillReverseReason);
  Press(LFrame.btnReverse);
  LFrame.gridInstallments.Row := 1;
  Check(GridCell(LFrame.gridInstallments, 'Em aberto') = 'R$ 39,90', 'Estorno devolve o saldo');
  LFrame.gridInstallmentsClick(nil);
  Check(LFrame.gridSettlements.RowCount = 3, 'Original e compensatória aparecem');
end;

procedure TSmoke.FillTransfer(const AForm: TCustomForm);
var
  LForm: TFieldsDialog;
begin
  LForm := AForm as TFieldsDialog;
  LForm.SetText('quantity', '5');
  LForm.SetText('reason', 'Reposição da filial');
  { O combo abre no primeiro depósito (CD1), igual à origem: a validação tem de recusar. }
  LForm.btnOk.Click;
end;

procedure TSmoke.FillTransferDestination(const AForm: TCustomForm);
var
  LForm: TFieldsDialog;
begin
  LForm := AForm as TFieldsDialog;
  Check(Pos('devem ser diferentes', FLastMessage) > 0, 'Transferir para o mesmo depósito é recusado e o diálogo continua aberto');
  LForm.SelectIndex('to', 1);
  LForm.btnOk.Click;
end;

procedure TSmoke.FillAdjustment(const AForm: TCustomForm);
var
  LForm: TFieldsDialog;
begin
  LForm := AForm as TFieldsDialog;
  LForm.SetText('counted', '100');
  LForm.SetText('reason', 'Contagem de inventário');
  LForm.btnOk.Click;
end;

procedure TSmoke.ScenarioStock;
var
  LFrame: TStockFrame;
  LBefore: string;
begin
  OpenTab('Estoque');
  LFrame := Frame('Estoque') as TStockFrame;
  Check(LFrame.gridBalances.RowCount > 40, 'Saldos carregados');
  LFrame.gridBalances.Row := 1;
  LFrame.gridBalancesClick(nil);
  Check(LFrame.gridKardex.RowCount >= 2, 'Kardex do item selecionado');
  Shot('07-estoque');
  LBefore := GridCell(LFrame.gridBalances, 'Físico');

  Queue(FillTransfer);
  Queue(FillTransferDestination);
  Press(LFrame.btnTransfer);
  LFrame.gridBalances.Row := 1;
  Check(GridCell(LFrame.gridBalances, 'Físico') <> LBefore, 'Transferência debita a origem: ' + GridCell(LFrame.gridBalances, 'Físico'));

  Queue(FillAdjustment);
  Press(LFrame.btnAdjust);
  Check(Pos('aprovação', FLastMessage) > 0, 'Ajuste vai para aprovação');
  LFrame.pcStock.ActivePage := LFrame.tsAdjustments;
  LFrame.gridAdjustments.Row := 1;
  Check(GridCell(LFrame.gridAdjustments, 'Contagem') = '100', 'Ajuste pendente listado');
  Shot('07b-ajustes');
  Press(LFrame.btnApprove);
  Check(Pos('não pode aprová-lo', FLastMessage) > 0, 'Quem pediu o ajuste não aprova');
  LFrame.pcStock.ActivePage := LFrame.tsBalances;
end;

procedure TSmoke.FillPurchaseOrder(const AForm: TCustomForm);
var
  LForm: TLinesForm;
begin
  LForm := AForm as TLinesForm;
  LForm.edtSearch.Text := 'DJ-TRI';
  LForm.btnSearch.Click;
  LForm.edtQuantity.Text := '10';
  LForm.edtCost.Text := '70,00';
  LForm.btnAdd.Click;
  LForm.btnPrimary.Click;
end;

procedure TSmoke.FillReceipt(const AForm: TCustomForm);
var
  LForm: TFieldsDialog;
begin
  LForm := AForm as TFieldsDialog;
  LForm.SetText('qty0', '4');
  LForm.btnOk.Click;
end;

procedure TSmoke.ScenarioPurchases;
var
  LFrame: TPurchasesFrame;
begin
  OpenTab('Compras');
  LFrame := Frame('Compras') as TPurchasesFrame;
  Queue(FillPurchaseOrder);
  Press(LFrame.btnNew);
  LFrame.gridOrders.Row := 1;
  Check(GridCell(LFrame.gridOrders, 'Status') = 'OPEN', 'Pedido de compra criado');
  Queue(FillReceipt);
  Press(LFrame.btnReceive);
  LFrame.gridOrders.Row := 1;
  Check(GridCell(LFrame.gridOrders, 'Status') = 'PARTIALLY_RECEIVED', 'Recebimento parcial');
  LFrame.gridOrdersClick(nil);
  LFrame.gridItems.Row := 1;
  Check(GridCell(LFrame.gridItems, 'Falta') = '6', 'Falta calculada: ' + GridCell(LFrame.gridItems, 'Falta'));
  Shot('08-compras');
end;

procedure TSmoke.FillInvalidCustomer(const AForm: TCustomForm);
var
  LForm: TFieldsDialog;
begin
  LForm := AForm as TFieldsDialog;
  LForm.SetText('name', 'Cliente Novo Exemplo');
  LForm.SetText('document', '111.111.111-11');
  LForm.SetText('limit', '1.500,00');
  LForm.btnOk.Click;
end;

procedure TSmoke.FillValidCustomer(const AForm: TCustomForm);
var
  LForm: TFieldsDialog;
begin
  LForm := AForm as TFieldsDialog;
  Check(Pos('CPF ou CNPJ inválido', FLastMessage) > 0, 'CPF inválido é recusado e o diálogo continua aberto');
  LForm.SetText('document', '529.982.247-25');
  LForm.btnOk.Click;
end;

procedure TSmoke.ScenarioCatalog;
var
  LFrame: TCatalogFrame;
begin
  OpenTab('Cadastros');
  LFrame := Frame('Cadastros') as TCatalogFrame;
  Check(LFrame.gridProducts.RowCount >= 25, 'Produtos carregados');
  Shot('09-cadastros');
  LFrame.pcCatalog.ActivePage := LFrame.tsCustomers;
  Queue(FillInvalidCustomer);
  Queue(FillValidCustomer);
  Press(LFrame.btnCustomerNew);
  LFrame.edtCustomerSearch.Text := 'Cliente Novo';
  Press(LFrame.btnCustomerSearch);
  LFrame.gridCustomers.Row := 1;
  Check(GridCell(LFrame.gridCustomers, 'Limite de crédito') = 'R$ 1.500,00', 'Cliente novo salvo com limite');
  Check(GridCell(LFrame.gridCustomers, 'CPF/CNPJ') = '52998224725', 'Documento gravado só com dígitos');
  LFrame.pcCatalog.ActivePage := LFrame.tsUsers;
  Settle;
  Check(LFrame.gridUsers.RowCount >= 8, 'Usuários listados');
  Check(Pos('Hash', LFrame.gridUsers.Rows[0].Text) = 0, 'Hash de senha não vai para a tela');
end;

procedure TSmoke.ScenarioReports;
var
  LFrame: TReportsFrame;
  LIndex: Integer;
begin
  OpenTab('Relatórios');
  LFrame := Frame('Relatórios') as TReportsFrame;
  for LIndex := 0 to LFrame.cbReport.Items.Count - 1 do
  begin
    LFrame.cbReport.ItemIndex := LIndex;
    Press(LFrame.btnRun);
    Check(LFrame.grid.ColCount >= 2, 'Relatório gerado: ' + LFrame.cbReport.Items[LIndex]);
  end;
  LFrame.cbReport.ItemIndex := 4;
  Press(LFrame.btnRun);
  Check(LFrame.grid.Cells[1, 1] <> '', 'Estoque abaixo do mínimo lista algum item: ' + LFrame.grid.Cells[1, 1]);
  Shot('10-relatorios');
  LFrame.cbReport.ItemIndex := 5;
  Press(LFrame.btnRun);
  Check(LFrame.grid.Cells[1, 1] = '', 'Saldo e Kardex reconciliados depois de todo o roteiro');
end;

procedure TSmoke.ScenarioIntegration;
var
  LFrame: TIntegrationFrame;
  LTries: Integer;
  LSent: Boolean;
begin
  OpenTab('Integração');
  LFrame := Frame('Integração') as TIntegrationFrame;
  Check(LFrame.gridOutbox.RowCount >= 2, 'Evento do faturamento na outbox');
  LSent := False;
  for LTries := 1 to 40 do
  begin
    Press(LFrame.btnProcess);
    Sleep(200);
    Press(LFrame.btnRefresh);
    LFrame.gridOutbox.Row := 1;
    if GridCell(LFrame.gridOutbox, 'Status') = 'SENT' then
    begin
      LSent := True;
      Break;
    end;
  end;
  Check(LSent, 'Worker em segundo plano entrega o evento: ' + GridCell(LFrame.gridOutbox, 'Status'));
  Check(LFrame.gridLogs.RowCount >= 2, 'Tentativa registrada no log de integração');
  LFrame.pcIntegration.ActivePage := LFrame.tsMetrics;
  Shot('11-integracao');
end;

function TSmoke.Run: Integer;
var
  LSession: IDbSession;
begin
  FShots := GetEnvironmentVariable('EF_UI_SHOTS');
  if FShots <> '' then
    ForceDirectories(FShots);
  DomainMessageSink := Sink;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 40;
  FTimer.OnTimer := Pump;
  FTimer.Enabled := True;
  LSession := OpenSession(LoadConfig('').Db);
  FAuth := TAuthService.Create(NewAuthUow(LSession), TSystemClock.Create);
  try
    try
      ScenarioLogin;
      ScenarioSales;
      ScenarioFinance;
      ScenarioStock;
      ScenarioPurchases;
      ScenarioCatalog;
      ScenarioReports;
      ScenarioIntegration;
    except
      on E: Exception do
        Check(False, 'Exceção não esperada: ' + E.ClassName + ': ' + E.Message);
    end;
    Check(FNextAction > High(FActions), 'Todas as janelas esperadas apareceram');
  finally
    FTimer.Enabled := False;
    if FWorker <> nil then
      FWorker.Shutdown;
    FAuth.Free;
    FTimer.Free;
  end;
  WriteLn(Format('%d verificações, %d falhas', [FChecks, FFailures]));
  if FFailures > 0 then
    Result := 1
  else
    Result := 0;
end;

var
  GSmoke: TSmoke;
  GExit: Integer;
begin
  Application.Scaled := False;
  Application.Initialize;
  GSmoke := TSmoke.Create;
  GExit := GSmoke.Run;
  { Sai direto: fechar a janela principal aqui só repetiria o que o Application já faz. }
  Halt(GExit);
end.
