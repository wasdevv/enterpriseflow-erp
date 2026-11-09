unit EF.Presentation.CatalogFrame;

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Grids, ComCtrls,
  EF.Application.Ports, EF.Presentation.Common;

type
  TCatalogFrame = class(TModuleFrame)
    pcCatalog: TPageControl;
    tsProducts: TTabSheet;
    pnlProducts: TPanel;
    edtProductSearch: TEdit;
    btnProductSearch: TButton;
    btnProductNew: TButton;
    btnProductEdit: TButton;
    btnProductHistory: TButton;
    gridProducts: TStringGrid;
    tsCustomers: TTabSheet;
    pnlCustomers: TPanel;
    edtCustomerSearch: TEdit;
    btnCustomerSearch: TButton;
    btnCustomerNew: TButton;
    btnCustomerEdit: TButton;
    btnCustomerHistory: TButton;
    gridCustomers: TStringGrid;
    tsSuppliers: TTabSheet;
    pnlSuppliers: TPanel;
    btnSupplierNew: TButton;
    btnSupplierEdit: TButton;
    gridSuppliers: TStringGrid;
    tsCarriers: TTabSheet;
    pnlCarriers: TPanel;
    btnCarrierNew: TButton;
    btnCarrierEdit: TButton;
    gridCarriers: TStringGrid;
    tsWarehouses: TTabSheet;
    pnlWarehouses: TPanel;
    btnWarehouseNew: TButton;
    btnWarehouseEdit: TButton;
    btnLocationAdd: TButton;
    gridWarehouses: TStringGrid;
    splWarehouses: TSplitter;
    gridLocations: TStringGrid;
    tsUsers: TTabSheet;
    pnlUsers: TPanel;
    btnUserNew: TButton;
    gridUsers: TStringGrid;
    procedure btnProductSearchClick(Sender: TObject);
    procedure btnProductNewClick(Sender: TObject);
    procedure btnProductEditClick(Sender: TObject);
    procedure btnProductHistoryClick(Sender: TObject);
    procedure btnCustomerSearchClick(Sender: TObject);
    procedure btnCustomerNewClick(Sender: TObject);
    procedure btnCustomerEditClick(Sender: TObject);
    procedure btnCustomerHistoryClick(Sender: TObject);
    procedure btnSupplierNewClick(Sender: TObject);
    procedure btnSupplierEditClick(Sender: TObject);
    procedure btnCarrierNewClick(Sender: TObject);
    procedure btnCarrierEditClick(Sender: TObject);
    procedure btnWarehouseNewClick(Sender: TObject);
    procedure btnWarehouseEditClick(Sender: TObject);
    procedure btnLocationAddClick(Sender: TObject);
    procedure gridWarehousesClick(Sender: TObject);
    procedure btnUserNewClick(Sender: TObject);
  private
    procedure EditProduct(const AId: Int64);
    procedure EditCustomer(const AId: Int64);
    procedure EditParty(const AKind: TPartyKind; const AGrid: TStringGrid; const AId: Int64);
    procedure EditWarehouse(const AId: Int64);
  public
    procedure Reload; override;
  end;

implementation

{$R *.dfm}

uses
  EF.Domain.Exceptions, EF.Domain.Money, EF.Domain.Quantity,
  EF.Presentation.Fields, EF.Presentation.TableView;

procedure TCatalogFrame.Reload;
var
  LCanManage: Boolean;
begin
  FillGrid(gridProducts, FApp.ReadModel.Products(edtProductSearch.Text));
  FillGrid(gridCustomers, FApp.ReadModel.Customers(edtCustomerSearch.Text));
  FillGrid(gridSuppliers, FApp.ReadModel.Parties(pkSupplier));
  FillGrid(gridCarriers, FApp.ReadModel.Parties(pkCarrier));
  FillGrid(gridWarehouses, FApp.ReadModel.Warehouses);
  gridWarehousesClick(nil);
  LCanManage := FApp.Context.Has(PermCatalogManage);
  btnProductNew.Enabled := LCanManage;
  btnProductEdit.Enabled := LCanManage;
  btnCustomerNew.Enabled := LCanManage;
  btnCustomerEdit.Enabled := LCanManage;
  btnSupplierNew.Enabled := LCanManage;
  btnSupplierEdit.Enabled := LCanManage;
  btnCarrierNew.Enabled := LCanManage;
  btnCarrierEdit.Enabled := LCanManage;
  btnWarehouseNew.Enabled := LCanManage;
  btnWarehouseEdit.Enabled := LCanManage;
  btnLocationAdd.Enabled := LCanManage;
  tsUsers.TabVisible := FApp.Context.Has(PermUsersManage);
  if tsUsers.TabVisible then
    FillGrid(gridUsers, FApp.ReadModel.Users);
end;

procedure TCatalogFrame.btnProductSearchClick(Sender: TObject);
begin
  FillGrid(gridProducts, FApp.ReadModel.Products(edtProductSearch.Text));
end;

procedure TCatalogFrame.btnProductNewClick(Sender: TObject);
begin
  EditProduct(0);
end;

procedure TCatalogFrame.btnProductEditClick(Sender: TObject);
begin
  EditProduct(RequireGridId(gridProducts, 'um produto'));
end;

procedure TCatalogFrame.btnProductHistoryClick(Sender: TObject);
begin
  TTableViewForm.ShowTable(Self, 'Histórico do produto', FApp.ReadModel.AuditTrail('product', RequireGridId(gridProducts, 'um produto')));
end;

procedure TCatalogFrame.EditProduct(const AId: Int64);
var
  LDialog: TFieldsDialog;
  LProduct: TProductRecord;
begin
  LProduct.Id := AId;
  LProduct.CategoryId := 0;
  LProduct.Sku := '';
  LProduct.Name := '';
  LProduct.UnitCode := 'UN';
  LProduct.SalePrice := TMoney.Zero;
  LProduct.MinimumStock := TQuantity.Zero;
  LProduct.IsActive := True;
  if AId <> 0 then
    LProduct := FApp.Catalog.GetProduct(AId);
  LDialog := TFieldsDialog.CreateDialog(Self, 'Produto');
  try
    LDialog.AddText('sku', 'SKU', LProduct.Sku);
    LDialog.AddText('name', 'Nome', LProduct.Name);
    LDialog.AddCombo('category', 'Categoria', FApp.ReadModel.Categories, 'ID', 'Categoria', LProduct.CategoryId, True);
    LDialog.AddText('unit', 'Unidade (UN, M, RL, CX)', LProduct.UnitCode);
    LDialog.AddText('price', 'Preço de venda', LProduct.SalePrice.ToDisplay);
    LDialog.AddText('minimum', 'Estoque mínimo', LProduct.MinimumStock.ToText);
    LDialog.AddCheck('active', 'Ativo', LProduct.IsActive);
    while LDialog.Execute do
      try
        LProduct.Sku := LDialog.Text('sku');
        LProduct.Name := LDialog.Text('name');
        LProduct.CategoryId := LDialog.SelectedId('category');
        LProduct.UnitCode := UpperCase(LDialog.Text('unit'));
        LProduct.SalePrice := TMoney.Parse(LDialog.Text('price'));
        LProduct.MinimumStock := TQuantity.Parse(LDialog.Text('minimum'));
        LProduct.IsActive := LDialog.Checked('active');
        FApp.Catalog.SaveProduct(LProduct);
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

procedure TCatalogFrame.btnCustomerSearchClick(Sender: TObject);
begin
  FillGrid(gridCustomers, FApp.ReadModel.Customers(edtCustomerSearch.Text));
end;

procedure TCatalogFrame.btnCustomerNewClick(Sender: TObject);
begin
  EditCustomer(0);
end;

procedure TCatalogFrame.btnCustomerEditClick(Sender: TObject);
begin
  EditCustomer(RequireGridId(gridCustomers, 'um cliente'));
end;

procedure TCatalogFrame.btnCustomerHistoryClick(Sender: TObject);
begin
  TTableViewForm.ShowTable(Self, 'Histórico do cliente', FApp.ReadModel.AuditTrail('customer', RequireGridId(gridCustomers, 'um cliente')));
end;

procedure TCatalogFrame.EditCustomer(const AId: Int64);
var
  LDialog: TFieldsDialog;
  LCustomer: TCustomerRecord;
begin
  LCustomer.Id := AId;
  LCustomer.Name := '';
  LCustomer.Document := '';
  LCustomer.Email := '';
  LCustomer.Phone := '';
  LCustomer.CreditLimit := TMoney.Zero;
  LCustomer.IsActive := True;
  if AId <> 0 then
    LCustomer := FApp.Catalog.GetCustomer(AId);
  LDialog := TFieldsDialog.CreateDialog(Self, 'Cliente');
  try
    LDialog.AddText('name', 'Nome', LCustomer.Name);
    LDialog.AddText('document', 'CPF ou CNPJ', LCustomer.Document);
    LDialog.AddText('email', 'E-mail', LCustomer.Email);
    LDialog.AddText('phone', 'Telefone', LCustomer.Phone);
    LDialog.AddText('limit', 'Limite de crédito', LCustomer.CreditLimit.ToDisplay);
    LDialog.AddCheck('active', 'Ativo', LCustomer.IsActive);
    while LDialog.Execute do
      try
        LCustomer.Name := LDialog.Text('name');
        LCustomer.Document := LDialog.Text('document');
        LCustomer.Email := LDialog.Text('email');
        LCustomer.Phone := LDialog.Text('phone');
        LCustomer.CreditLimit := TMoney.Parse(LDialog.Text('limit'));
        LCustomer.IsActive := LDialog.Checked('active');
        FApp.Catalog.SaveCustomer(LCustomer);
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

procedure TCatalogFrame.EditParty(const AKind: TPartyKind; const AGrid: TStringGrid; const AId: Int64);
var
  LDialog: TFieldsDialog;
  LParty: TPartyRecord;
  LNameColumn: string;
begin
  if AKind = pkSupplier then
    LNameColumn := 'Fornecedor'
  else
    LNameColumn := 'Transportadora';
  LParty.Id := AId;
  LParty.Kind := AKind;
  LParty.Name := '';
  LParty.Document := '';
  LParty.Email := '';
  LParty.Phone := '';
  LParty.IsActive := True;
  if AId <> 0 then
  begin
    LParty.Name := GridCell(AGrid, LNameColumn);
    LParty.Document := GridCell(AGrid, 'CNPJ');
    LParty.Email := GridCell(AGrid, 'E-mail');
    LParty.Phone := GridCell(AGrid, 'Telefone');
    LParty.IsActive := GridCell(AGrid, 'Ativo') = 'Sim';
  end;
  LDialog := TFieldsDialog.CreateDialog(Self, LNameColumn);
  try
    LDialog.AddText('name', 'Nome', LParty.Name);
    LDialog.AddText('document', 'CNPJ', LParty.Document);
    if AKind = pkSupplier then
      LDialog.AddText('email', 'E-mail', LParty.Email);
    LDialog.AddText('phone', 'Telefone', LParty.Phone);
    LDialog.AddCheck('active', 'Ativo', LParty.IsActive);
    while LDialog.Execute do
      try
        LParty.Name := LDialog.Text('name');
        LParty.Document := LDialog.Text('document');
        if AKind = pkSupplier then
          LParty.Email := LDialog.Text('email');
        LParty.Phone := LDialog.Text('phone');
        LParty.IsActive := LDialog.Checked('active');
        FApp.Catalog.SaveParty(LParty);
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

procedure TCatalogFrame.btnSupplierNewClick(Sender: TObject);
begin
  EditParty(pkSupplier, gridSuppliers, 0);
end;

procedure TCatalogFrame.btnSupplierEditClick(Sender: TObject);
begin
  EditParty(pkSupplier, gridSuppliers, RequireGridId(gridSuppliers, 'um fornecedor'));
end;

procedure TCatalogFrame.btnCarrierNewClick(Sender: TObject);
begin
  EditParty(pkCarrier, gridCarriers, 0);
end;

procedure TCatalogFrame.btnCarrierEditClick(Sender: TObject);
begin
  EditParty(pkCarrier, gridCarriers, RequireGridId(gridCarriers, 'uma transportadora'));
end;

procedure TCatalogFrame.EditWarehouse(const AId: Int64);
var
  LDialog: TFieldsDialog;
  LWarehouse: TWarehouseRecord;
begin
  LWarehouse.Id := AId;
  LWarehouse.Code := '';
  LWarehouse.Name := '';
  LWarehouse.IsActive := True;
  if AId <> 0 then
  begin
    LWarehouse.Code := GridCell(gridWarehouses, 'Código');
    LWarehouse.Name := GridCell(gridWarehouses, 'Depósito');
    LWarehouse.IsActive := GridCell(gridWarehouses, 'Ativo') = 'Sim';
  end;
  LDialog := TFieldsDialog.CreateDialog(Self, 'Depósito');
  try
    LDialog.AddText('code', 'Código', LWarehouse.Code);
    LDialog.AddText('name', 'Nome', LWarehouse.Name);
    LDialog.AddCheck('active', 'Ativo', LWarehouse.IsActive);
    while LDialog.Execute do
      try
        LWarehouse.Code := LDialog.Text('code');
        LWarehouse.Name := LDialog.Text('name');
        LWarehouse.IsActive := LDialog.Checked('active');
        FApp.Catalog.SaveWarehouse(LWarehouse);
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

procedure TCatalogFrame.btnWarehouseNewClick(Sender: TObject);
begin
  EditWarehouse(0);
end;

procedure TCatalogFrame.btnWarehouseEditClick(Sender: TObject);
begin
  EditWarehouse(RequireGridId(gridWarehouses, 'um depósito'));
end;

procedure TCatalogFrame.btnLocationAddClick(Sender: TObject);
var
  LCode: string;
  LWarehouse: Int64;
begin
  LWarehouse := RequireGridId(gridWarehouses, 'um depósito');
  if AskRequiredText('Endereço de armazenamento', 'Código (ex.: A-01-03):', LCode) then
  begin
    FApp.Catalog.AddLocation(LWarehouse, LCode, '');
    gridWarehousesClick(nil);
  end;
end;

procedure TCatalogFrame.gridWarehousesClick(Sender: TObject);
begin
  FillGrid(gridLocations, FApp.ReadModel.Locations(GridId(gridWarehouses)));
end;

procedure TCatalogFrame.btnUserNewClick(Sender: TObject);
var
  LDialog: TFieldsDialog;
begin
  LDialog := TFieldsDialog.CreateDialog(Self, 'Usuário');
  try
    LDialog.AddText('username', 'Login', '');
    LDialog.AddText('name', 'Nome completo', '');
    LDialog.AddText('password', 'Senha inicial', '', True);
    LDialog.AddCombo('role', 'Perfil', FApp.ReadModel.Roles, 'ID', 'Perfil');
    while LDialog.Execute do
      try
        FApp.Auth.CreateUser(FApp.Context, LDialog.Text('username'), LDialog.Text('name'), LDialog.Text('password'), [LDialog.SelectedText('role')]);
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

end.
