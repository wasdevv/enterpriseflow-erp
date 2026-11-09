unit EF.Presentation.SalesFrame;

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Grids, ComCtrls,
  EF.Application.Ports, EF.Infrastructure.Composition, EF.Presentation.Common;

type
  { A tela pede ações ao serviço; nenhum botão escreve status. Quem decide se a transição vale
    é a máquina de estados, e a recusa chega como mensagem clara. }
  TSalesFrame = class(TModuleFrame)
    pnlTop: TPanel;
    lblStatus: TLabel;
    cbStatus: TComboBox;
    btnNew: TButton;
    btnConfirm: TButton;
    btnPick: TButton;
    btnShip: TButton;
    btnInvoice: TButton;
    btnCancelOrder: TButton;
    gridOrders: TStringGrid;
    splDetail: TSplitter;
    pcDetail: TPageControl;
    tsItems: TTabSheet;
    gridItems: TStringGrid;
    tsHistory: TTabSheet;
    gridHistory: TStringGrid;
    procedure cbStatusChange(Sender: TObject);
    procedure gridOrdersClick(Sender: TObject);
    procedure btnNewClick(Sender: TObject);
    procedure btnConfirmClick(Sender: TObject);
    procedure btnPickClick(Sender: TObject);
    procedure btnShipClick(Sender: TObject);
    procedure btnInvoiceClick(Sender: TObject);
    procedure btnCancelOrderClick(Sender: TObject);
  public
    procedure Bind(const AApp: TAppServices); override;
    procedure Reload; override;
  end;

implementation

{$R *.dfm}

uses
  EF.Domain.Exceptions, EF.Application.Sales,
  EF.Presentation.Fields, EF.Presentation.Lines, EF.Shared.Text;

const
  CStatuses: array [0 .. 7] of string = ('', 'DRAFT', 'CONFIRMED', 'RESERVED', 'PICKING', 'SHIPPED', 'INVOICED', 'CANCELLED');

procedure TSalesFrame.Bind(const AApp: TAppServices);
var
  LIndex: Integer;
begin
  inherited;
  cbStatus.Items.Clear;
  cbStatus.Items.Add('Todos');
  for LIndex := 1 to High(CStatuses) do
    cbStatus.Items.Add(CStatuses[LIndex]);
  cbStatus.ItemIndex := 0;
end;

procedure TSalesFrame.Reload;
begin
  FillGrid(gridOrders, FApp.ReadModel.SalesOrders(CStatuses[cbStatus.ItemIndex]));
  gridOrdersClick(nil);
  btnNew.Enabled := FApp.Context.Has(PermOrderCreate) or FApp.Context.Has(PermOrderConfirm);
  btnConfirm.Enabled := FApp.Context.Has(PermOrderConfirm);
  btnPick.Enabled := FApp.Context.Has(PermOrderFulfill);
  btnShip.Enabled := FApp.Context.Has(PermOrderFulfill);
  btnInvoice.Enabled := FApp.Context.Has(PermInvoiceCreate);
  btnCancelOrder.Enabled := FApp.Context.Has(PermOrderCancel);
end;

procedure TSalesFrame.cbStatusChange(Sender: TObject);
begin
  Reload;
end;

procedure TSalesFrame.gridOrdersClick(Sender: TObject);
var
  LOrder: Int64;
begin
  LOrder := GridId(gridOrders);
  FillGrid(gridItems, FApp.ReadModel.SalesOrderItems(LOrder));
  FillGrid(gridHistory, FApp.ReadModel.SalesOrderHistory(LOrder));
end;

procedure TSalesFrame.btnNewClick(Sender: TObject);
var
  LForm: TLinesForm;
  LAction: TLinesAction;
  LCommand: TNewOrderCommand;
  LEntries: TLineEntries;
  LIndex: Integer;
  LKey: string;
begin
  { Chave criada ao abrir: clique duplo em "Confirmar" não gera segundo pedido. }
  LKey := NewCorrelationId;
  LForm := nil;
  try
    LAction := TLinesForm.Execute(Self, FApp, lmSale, LForm);
    if LAction = laCancel then
      Exit;
    LEntries := LForm.Lines;
    LCommand.CustomerId := LForm.PartyId;
    LCommand.CarrierId := LForm.CarrierId;
    LCommand.Installments := LForm.Installments;
    LCommand.IntervalDays := LForm.IntervalDays;
    LCommand.IdempotencyKey := LKey;
    SetLength(LCommand.Lines, Length(LEntries));
    for LIndex := 0 to High(LEntries) do
    begin
      LCommand.Lines[LIndex].ProductId := LEntries[LIndex].ProductId;
      LCommand.Lines[LIndex].WarehouseId := LEntries[LIndex].WarehouseId;
      LCommand.Lines[LIndex].Quantity := LEntries[LIndex].Quantity;
    end;
    if LAction = laPrimary then
      FApp.Sales.ConfirmNew(LCommand)
    else
      FApp.Sales.CreateDraft(LCommand);
    Reload;
  finally
    LForm.Free;
  end;
end;

procedure TSalesFrame.btnConfirmClick(Sender: TObject);
begin
  FApp.Sales.ConfirmDraft(RequireGridId(gridOrders, 'um pedido'), NewCorrelationId);
  Reload;
end;

procedure TSalesFrame.btnPickClick(Sender: TObject);
begin
  FApp.Sales.StartPicking(RequireGridId(gridOrders, 'um pedido'));
  Reload;
end;

procedure TSalesFrame.btnShipClick(Sender: TObject);
var
  LOrder: Int64;
  LDialog: TFieldsDialog;
begin
  LOrder := RequireGridId(gridOrders, 'um pedido');
  LDialog := TFieldsDialog.CreateDialog(Self, 'Expedir pedido ' + IntToStr(LOrder));
  try
    LDialog.AddCombo('carrier', 'Transportadora', FApp.ReadModel.Parties(pkCarrier), 'ID', 'Transportadora', 0, True);
    if LDialog.Execute then
    begin
      FApp.Sales.Ship(LOrder, LDialog.SelectedId('carrier'));
      Reload;
    end;
  finally
    LDialog.Free;
  end;
end;

procedure TSalesFrame.btnInvoiceClick(Sender: TObject);
var
  LOrder: Int64;
  LDialog: TFieldsDialog;
begin
  LOrder := RequireGridId(gridOrders, 'um pedido');
  LDialog := TFieldsDialog.CreateDialog(Self, 'Faturar pedido ' + IntToStr(LOrder));
  try
    LDialog.AddText('due', '1º vencimento (dd/mm/aaaa)', FormatDateTime('dd"/"mm"/"yyyy', FApp.Clock.Today + 30));
    while LDialog.Execute do
      try
        FApp.Invoicing.InvoiceOrder(LOrder, ParseBrazilianDate(LDialog.Text('due')));
        Reload;
        Break;
      except
        on E: EDomainError do
          ShowDomainMessage(E.Message);
      end;
  finally
    LDialog.Free;
  end;
end;

procedure TSalesFrame.btnCancelOrderClick(Sender: TObject);
var
  LReason: string;
begin
  if AskRequiredText('Cancelar pedido', 'Motivo do cancelamento:', LReason) then
  begin
    FApp.Sales.Cancel(RequireGridId(gridOrders, 'um pedido'), LReason);
    Reload;
  end;
end;

end.
