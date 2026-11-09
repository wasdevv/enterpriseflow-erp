unit EF.Presentation.ReportsFrame;

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Grids, Dialogs,
  EF.Application.Ports, EF.Infrastructure.Composition, EF.Presentation.Common;

type
  TReportsFrame = class(TModuleFrame)
    pnlTop: TPanel;
    cbReport: TComboBox;
    lblFrom: TLabel;
    edtFrom: TEdit;
    lblTo: TLabel;
    edtTo: TEdit;
    btnRun: TButton;
    btnExport: TButton;
    grid: TStringGrid;
    dlgSave: TSaveDialog;
    procedure btnRunClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
  private
    FTable: TDataTable;
  public
    procedure Bind(const AApp: TAppServices); override;
    procedure Reload; override;
  end;

implementation

{$R *.dfm}

uses
  EF.Domain.Exceptions, EF.Infrastructure.Reporting, EF.Shared.Text;

const
  CReports: array [0 .. 7] of string = (
    'Títulos em aberto', 'Títulos vencidos', 'Fluxo de caixa previsto e realizado', 'Fila de pedidos',
    'Estoque abaixo do mínimo', 'Reconciliação de saldo com Kardex', 'Divergências de compra', 'Métricas operacionais');

procedure TReportsFrame.Bind(const AApp: TAppServices);
var
  LIndex: Integer;
begin
  inherited;
  cbReport.Items.Clear;
  for LIndex := Low(CReports) to High(CReports) do
    cbReport.Items.Add(CReports[LIndex]);
  cbReport.ItemIndex := 0;
  edtFrom.Text := FormatDateTime('dd"/"mm"/"yyyy', AApp.Clock.Today - 30);
  edtTo.Text := FormatDateTime('dd"/"mm"/"yyyy', AApp.Clock.Today + 60);
end;

procedure TReportsFrame.Reload;
begin
  btnRunClick(nil);
end;

procedure TReportsFrame.btnRunClick(Sender: TObject);
begin
  case cbReport.ItemIndex of
    0: FTable := FApp.ReadModel.OpenInstallments(FApp.Clock.Today, False);
    1: FTable := FApp.ReadModel.OpenInstallments(FApp.Clock.Today, True);
    2: FTable := FApp.ReadModel.CashFlow(ParseBrazilianDate(edtFrom.Text), ParseBrazilianDate(edtTo.Text));
    3: FTable := FApp.ReadModel.SalesOrders('');
    4: FTable := FApp.ReadModel.LowStock;
    5: FTable := FApp.ReadModel.StockReconciliation;
    6: FTable := FApp.ReadModel.PurchaseDivergences;
  else
    FTable := FApp.ReadModel.MetricsSummary;
  end;
  FillGrid(grid, FTable);
end;

procedure TReportsFrame.btnExportClick(Sender: TObject);
begin
  if Length(FTable.Columns) = 0 then
    raise EValidationError.Create('Gere um relatório antes de exportar.');
  if dlgSave.Execute then
    SaveDataTableCsv(FTable, dlgSave.FileName);
end;

end.
