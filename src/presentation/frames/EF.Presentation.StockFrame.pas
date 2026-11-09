unit EF.Presentation.StockFrame;

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Grids, ComCtrls,
  EF.Application.Ports, EF.Presentation.Common;

type
  TStockFrame = class(TModuleFrame)
    pcStock: TPageControl;
    tsBalances: TTabSheet;
    pnlBalances: TPanel;
    edtSearch: TEdit;
    btnSearch: TButton;
    btnTransfer: TButton;
    btnAdjust: TButton;
    gridBalances: TStringGrid;
    splKardex: TSplitter;
    gridKardex: TStringGrid;
    tsAdjustments: TTabSheet;
    pnlAdjustments: TPanel;
    btnApprove: TButton;
    btnReject: TButton;
    gridAdjustments: TStringGrid;
    procedure btnSearchClick(Sender: TObject);
    procedure gridBalancesClick(Sender: TObject);
    procedure btnTransferClick(Sender: TObject);
    procedure btnAdjustClick(Sender: TObject);
    procedure btnApproveClick(Sender: TObject);
    procedure btnRejectClick(Sender: TObject);
  public
    procedure Reload; override;
  end;

implementation

{$R *.dfm}

uses
  EF.Domain.Exceptions, EF.Domain.Quantity,
  EF.Presentation.Fields;

procedure TStockFrame.Reload;
begin
  FillGrid(gridBalances, FApp.ReadModel.StockBalances(edtSearch.Text));
  gridBalancesClick(nil);
  FillGrid(gridAdjustments, FApp.ReadModel.PendingAdjustments);
  btnTransfer.Enabled := FApp.Context.Has(PermStockMove);
  btnAdjust.Enabled := FApp.Context.Has(PermStockAdjustRequest);
  btnApprove.Enabled := FApp.Context.Has(PermStockAdjustApprove);
  btnReject.Enabled := btnApprove.Enabled;
end;

procedure TStockFrame.btnSearchClick(Sender: TObject);
begin
  Reload;
end;

procedure TStockFrame.gridBalancesClick(Sender: TObject);
begin
  FillGrid(gridKardex, FApp.ReadModel.Kardex(GridId(gridBalances, 'PRODUCT_ID'), GridId(gridBalances, 'WAREHOUSE_ID')));
end;

procedure TStockFrame.btnTransferClick(Sender: TObject);
var
  LDialog: TFieldsDialog;
  LProduct, LFrom: Int64;
begin
  LProduct := RequireGridId(gridBalances, 'um saldo', 'PRODUCT_ID');
  LFrom := GridId(gridBalances, 'WAREHOUSE_ID');
  LDialog := TFieldsDialog.CreateDialog(Self, 'Transferência de ' + GridCell(gridBalances, 'SKU'));
  try
    LDialog.AddCombo('to', 'Depósito de destino', FApp.ReadModel.Warehouses, 'ID', 'Depósito');
    LDialog.AddText('quantity', 'Quantidade', '');
    LDialog.AddText('reason', 'Motivo', '');
    while LDialog.Execute do
      try
        FApp.Stock.Transfer(LProduct, LFrom, LDialog.SelectedId('to'), TQuantity.Parse(LDialog.Text('quantity')), LDialog.Text('reason'));
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

procedure TStockFrame.btnAdjustClick(Sender: TObject);
var
  LDialog: TFieldsDialog;
  LProduct, LWarehouse: Int64;
begin
  LProduct := RequireGridId(gridBalances, 'um saldo', 'PRODUCT_ID');
  LWarehouse := GridId(gridBalances, 'WAREHOUSE_ID');
  LDialog := TFieldsDialog.CreateDialog(Self, 'Ajuste de inventário de ' + GridCell(gridBalances, 'SKU'));
  try
    LDialog.AddText('counted', 'Quantidade contada', GridCell(gridBalances, 'Físico'));
    LDialog.AddText('reason', 'Justificativa', '');
    while LDialog.Execute do
      try
        FApp.Stock.RequestAdjustment(LProduct, LWarehouse, TQuantity.Parse(LDialog.Text('counted')), LDialog.Text('reason'));
        ShowDomainMessage('Ajuste enviado para aprovação. O saldo muda só depois que outra pessoa aprovar.');
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

procedure TStockFrame.btnApproveClick(Sender: TObject);
begin
  FApp.Stock.ApproveAdjustment(RequireGridId(gridAdjustments, 'um ajuste'));
  Reload;
end;

procedure TStockFrame.btnRejectClick(Sender: TObject);
begin
  FApp.Stock.RejectAdjustment(RequireGridId(gridAdjustments, 'um ajuste'));
  Reload;
end;

end.
