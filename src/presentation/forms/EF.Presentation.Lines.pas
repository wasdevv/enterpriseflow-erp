unit EF.Presentation.Lines;

{ Entrada de pedido com itens, para venda e compra. Os totais exibidos são informativos: o
  preço de venda e o saldo são revalidados pelo serviço, dentro da transação. }

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Grids,
  EF.Domain.Money, EF.Domain.Quantity,
  EF.Application.Ports, EF.Infrastructure.Composition;

type
  TLinesMode = (lmSale, lmPurchase);
  TLinesAction = (laCancel, laPrimary, laSecondary);

  TLineEntry = record
    ProductId, WarehouseId: Int64;
    Quantity: TQuantity;
    UnitCost: TMoney;
  end;
  TLineEntries = array of TLineEntry;

  TLinesForm = class(TForm)
    pnlHeader: TPanel;
    lblParty: TLabel;
    cbParty: TComboBox;
    lblWarehouse: TLabel;
    cbWarehouse: TComboBox;
    lblCarrier: TLabel;
    cbCarrier: TComboBox;
    lblInstallments: TLabel;
    edtInstallments: TEdit;
    lblInterval: TLabel;
    edtInterval: TEdit;
    pnlAdd: TPanel;
    lblSearch: TLabel;
    edtSearch: TEdit;
    btnSearch: TButton;
    cbProduct: TComboBox;
    lblQuantity: TLabel;
    edtQuantity: TEdit;
    lblCost: TLabel;
    edtCost: TEdit;
    btnAdd: TButton;
    btnRemove: TButton;
    gridLines: TStringGrid;
    pnlButtons: TPanel;
    btnPrimary: TButton;
    btnSecondary: TButton;
    btnCancel: TButton;
    procedure btnSearchClick(Sender: TObject);
    procedure btnAddClick(Sender: TObject);
    procedure btnRemoveClick(Sender: TObject);
    procedure btnPrimaryClick(Sender: TObject);
    procedure btnSecondaryClick(Sender: TObject);
  private
    FApp: TAppServices;
    FMode: TLinesMode;
    FLines: TLineEntries;
    FTexts: array of TTextArray;
    FAction: TLinesAction;
    procedure LoadProducts;
    procedure RefreshGrid;
    procedure SetupMode;
    procedure EnsureHasLines;
  public
    class function Execute(const AOwner: TComponent; const AApp: TAppServices; const AMode: TLinesMode; out AForm: TLinesForm): TLinesAction;
    function Lines: TLineEntries;
    function PartyId: Int64;
    function WarehouseId: Int64;
    function CarrierId: Int64;
    function Installments: Integer;
    function IntervalDays: Integer;
  end;

implementation

{$R *.dfm}

uses
  EF.Domain.Exceptions, EF.Presentation.Common;

class function TLinesForm.Execute(const AOwner: TComponent; const AApp: TAppServices; const AMode: TLinesMode; out AForm: TLinesForm): TLinesAction;
begin
  AForm := TLinesForm.Create(AOwner);
  AForm.FApp := AApp;
  AForm.FMode := AMode;
  AForm.FAction := laCancel;
  AForm.SetupMode;
  AForm.ShowModal;
  Result := AForm.FAction;
end;

procedure TLinesForm.SetupMode;
var
  LIsSale: Boolean;
begin
  LIsSale := FMode = lmSale;
  FillCombo(cbWarehouse, FApp.ReadModel.Warehouses, 'ID', 'Depósito');
  if LIsSale then
  begin
    Caption := 'Novo pedido de venda';
    lblParty.Caption := 'Cliente';
    FillCombo(cbParty, FApp.ReadModel.Customers(''), 'ID', 'Cliente');
    FillCombo(cbCarrier, FApp.ReadModel.Parties(pkCarrier), 'ID', 'Transportadora', True);
    btnPrimary.Caption := 'Confirmar e reservar';
    btnSecondary.Caption := 'Salvar orçamento';
  end
  else
  begin
    Caption := 'Novo pedido de compra';
    lblParty.Caption := 'Fornecedor';
    FillCombo(cbParty, FApp.ReadModel.Parties(pkSupplier), 'ID', 'Fornecedor');
    btnPrimary.Caption := 'Criar pedido de compra';
  end;
  lblCarrier.Visible := LIsSale;
  cbCarrier.Visible := LIsSale;
  lblInstallments.Visible := LIsSale;
  edtInstallments.Visible := LIsSale;
  lblInterval.Visible := LIsSale;
  edtInterval.Visible := LIsSale;
  btnSecondary.Visible := LIsSale;
  lblCost.Visible := not LIsSale;
  edtCost.Visible := not LIsSale;
  LoadProducts;
  RefreshGrid;
end;

procedure TLinesForm.LoadProducts;
var
  LTable: TDataTable;
  LRow: Integer;
begin
  LTable := FApp.ReadModel.Products(edtSearch.Text);
  cbProduct.Items.BeginUpdate;
  try
    cbProduct.Items.Clear;
    for LRow := 0 to High(LTable.Rows) do
      cbProduct.Items.AddObject(LTable.Cell(LRow, 'SKU') + ' - ' + LTable.Cell(LRow, 'Produto') + ' (' + LTable.Cell(LRow, 'Preço') + ')',
        TObject(NativeInt(StrToInt64(LTable.Cell(LRow, 'ID')))));
  finally
    cbProduct.Items.EndUpdate;
  end;
  if cbProduct.Items.Count > 0 then
    cbProduct.ItemIndex := 0;
end;

procedure TLinesForm.RefreshGrid;
var
  LTable: TDataTable;
  LRow: Integer;
begin
  SetLength(LTable.Columns, 3);
  LTable.Columns[0] := 'Produto';
  LTable.Columns[1] := 'Depósito';
  LTable.Columns[2] := 'Quantidade';
  SetLength(LTable.Rows, Length(FTexts));
  for LRow := 0 to High(FTexts) do
    LTable.Rows[LRow] := FTexts[LRow];
  FillGrid(gridLines, LTable);
end;

procedure TLinesForm.btnSearchClick(Sender: TObject);
begin
  LoadProducts;
end;

procedure TLinesForm.btnAddClick(Sender: TObject);
var
  LIndex: Integer;
  LEntry: TLineEntry;
begin
  if cbProduct.ItemIndex < 0 then
    raise EValidationError.Create('Escolha um produto.');
  LEntry.ProductId := NativeInt(cbProduct.Items.Objects[cbProduct.ItemIndex]);
  LEntry.WarehouseId := ComboId(cbWarehouse);
  LEntry.Quantity := TQuantity.Parse(edtQuantity.Text);
  if FMode = lmPurchase then
    LEntry.UnitCost := TMoney.Parse(edtCost.Text)
  else
    LEntry.UnitCost := TMoney.Zero;
  LIndex := Length(FLines);
  SetLength(FLines, LIndex + 1);
  FLines[LIndex] := LEntry;
  SetLength(FTexts, LIndex + 1);
  SetLength(FTexts[LIndex], 3);
  FTexts[LIndex][0] := cbProduct.Text;
  FTexts[LIndex][1] := cbWarehouse.Text;
  FTexts[LIndex][2] := LEntry.Quantity.ToText;
  RefreshGrid;
  edtQuantity.Text := '';
end;

procedure TLinesForm.btnRemoveClick(Sender: TObject);
var
  LRow, LIndex: Integer;
begin
  LRow := gridLines.Row - 1;
  if (LRow < 0) or (LRow > High(FLines)) then
    Exit;
  for LIndex := LRow to High(FLines) - 1 do
  begin
    FLines[LIndex] := FLines[LIndex + 1];
    FTexts[LIndex] := FTexts[LIndex + 1];
  end;
  SetLength(FLines, Length(FLines) - 1);
  SetLength(FTexts, Length(FTexts) - 1);
  RefreshGrid;
end;

procedure TLinesForm.EnsureHasLines;
begin
  if Length(FLines) = 0 then
    raise EValidationError.Create('Adicione ao menos um item.');
  if PartyId = 0 then
    raise EValidationError.CreateFmt('Escolha: %s.', [lblParty.Caption]);
end;

procedure TLinesForm.btnPrimaryClick(Sender: TObject);
begin
  EnsureHasLines;
  FAction := laPrimary;
  ModalResult := mrOk;
end;

procedure TLinesForm.btnSecondaryClick(Sender: TObject);
begin
  EnsureHasLines;
  FAction := laSecondary;
  ModalResult := mrOk;
end;

function TLinesForm.Lines: TLineEntries;
begin
  Result := FLines;
end;

function TLinesForm.PartyId: Int64;
begin
  Result := ComboId(cbParty);
end;

function TLinesForm.WarehouseId: Int64;
begin
  Result := ComboId(cbWarehouse);
end;

function TLinesForm.CarrierId: Int64;
begin
  Result := ComboId(cbCarrier);
end;

function TLinesForm.Installments: Integer;
begin
  Result := StrToIntDef(edtInstallments.Text, 0);
end;

function TLinesForm.IntervalDays: Integer;
begin
  Result := StrToIntDef(edtInterval.Text, 0);
end;

end.
