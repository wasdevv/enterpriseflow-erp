unit EF.Presentation.PurchasesFrame;

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Grids,
  EF.Application.Ports, EF.Presentation.Common;

type
  TPurchasesFrame = class(TModuleFrame)
    pnlTop: TPanel;
    btnNew: TButton;
    btnReceive: TButton;
    btnCloseShort: TButton;
    gridOrders: TStringGrid;
    splItems: TSplitter;
    gridItems: TStringGrid;
    procedure btnNewClick(Sender: TObject);
    procedure btnReceiveClick(Sender: TObject);
    procedure btnCloseShortClick(Sender: TObject);
    procedure gridOrdersClick(Sender: TObject);
  public
    procedure Reload; override;
  end;

implementation

{$R *.dfm}

uses
  EF.Domain.Exceptions, EF.Domain.Quantity,
  EF.Application.Inventory,
  EF.Presentation.Fields, EF.Presentation.Lines, EF.Shared.Text;

procedure TPurchasesFrame.Reload;
var
  LCanManage: Boolean;
begin
  FillGrid(gridOrders, FApp.ReadModel.PurchaseOrders);
  gridOrdersClick(nil);
  LCanManage := FApp.Context.Has(PermPurchaseManage);
  btnNew.Enabled := LCanManage;
  btnReceive.Enabled := LCanManage;
  btnCloseShort.Enabled := LCanManage;
end;

procedure TPurchasesFrame.gridOrdersClick(Sender: TObject);
begin
  FillGrid(gridItems, FApp.ReadModel.PurchaseOrderItems(GridId(gridOrders)));
end;

procedure TPurchasesFrame.btnNewClick(Sender: TObject);
var
  LForm: TLinesForm;
  LEntries: TLineEntries;
  LLines: TPurchaseLineInputs;
  LIndex: Integer;
begin
  LForm := nil;
  try
    if TLinesForm.Execute(Self, FApp, lmPurchase, LForm) <> laPrimary then
      Exit;
    LEntries := LForm.Lines;
    SetLength(LLines, Length(LEntries));
    for LIndex := 0 to High(LEntries) do
    begin
      LLines[LIndex].ProductId := LEntries[LIndex].ProductId;
      LLines[LIndex].Quantity := LEntries[LIndex].Quantity;
      LLines[LIndex].UnitCost := LEntries[LIndex].UnitCost;
    end;
    FApp.Purchases.CreateOrder(LForm.PartyId, LForm.WarehouseId, LLines, '');
    Reload;
  finally
    LForm.Free;
  end;
end;

procedure TPurchasesFrame.btnReceiveClick(Sender: TObject);
var
  LOrder: Int64;
  LItems: TDataTable;
  LDialog: TFieldsDialog;
  LRow, LCount: Integer;
  LKey, LText: string;
  LLines: TReceiptLineInputs;
begin
  LOrder := RequireGridId(gridOrders, 'um pedido de compra');
  LItems := FApp.ReadModel.PurchaseOrderItems(LOrder);
  { Criada aqui, reaproveitada a cada nova tentativa: clique repetido não recebe duas vezes. }
  LKey := NewCorrelationId;
  LDialog := TFieldsDialog.CreateDialog(Self, 'Recebimento do pedido ' + IntToStr(LOrder));
  try
    for LRow := 0 to High(LItems.Rows) do
      LDialog.AddText('qty' + IntToStr(LRow), LItems.Cell(LRow, 'SKU') + ' (falta ' + LItems.Cell(LRow, 'Falta') + ')', LItems.Cell(LRow, 'Falta'));
    LDialog.AddText('note', 'Observação da divergência', '');
    while LDialog.Execute do
      try
        SetLength(LLines, 0);
        LCount := 0;
        for LRow := 0 to High(LItems.Rows) do
        begin
          LText := LDialog.Text('qty' + IntToStr(LRow));
          if (LText = '') or TQuantity.Parse(LText).IsZero then
            Continue;
          SetLength(LLines, LCount + 1);
          LLines[LCount].ItemId := StrToInt64(LItems.Cell(LRow, 'ID'));
          LLines[LCount].Quantity := TQuantity.Parse(LText);
          LLines[LCount].Note := LDialog.Text('note');
          Inc(LCount);
        end;
        FApp.Purchases.Receive(LOrder, LLines, LKey, LDialog.Text('note'));
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

procedure TPurchasesFrame.btnCloseShortClick(Sender: TObject);
var
  LReason: string;
begin
  if AskRequiredText('Encerrar com falta', 'Motivo:', LReason) then
  begin
    FApp.Purchases.CloseShort(RequireGridId(gridOrders, 'um pedido de compra'), LReason);
    Reload;
  end;
end;

end.
