object CatalogFrame: TCatalogFrame
  Left = 0
  Top = 0
  Width = 900
  Height = 600
  TabOrder = 0
  object pcCatalog: TPageControl
    Left = 0
    Top = 0
    Width = 900
    Height = 600
    ActivePage = tsProducts
    Align = alClient
    TabOrder = 53
    object tsProducts: TTabSheet
      Caption = 'Produtos'
      object pnlProducts: TPanel
        Left = 0
        Top = 0
        Width = 900
        Height = 42
        Align = alTop
        BevelOuter = bvNone
        Caption = ''
        TabOrder = 27
        object edtProductSearch: TEdit
          Left = 8
          Top = 9
          Width = 200
          Height = 24
          TabOrder = 22
          Text = ''
        end
        object btnProductSearch: TButton
          Left = 216
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Buscar'
          TabOrder = 23
          OnClick = btnProductSearchClick
        end
        object btnProductNew: TButton
          Left = 312
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Novo'
          TabOrder = 24
          OnClick = btnProductNewClick
        end
        object btnProductEdit: TButton
          Left = 408
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Editar'
          TabOrder = 25
          OnClick = btnProductEditClick
        end
        object btnProductHistory: TButton
          Left = 504
          Top = 8
          Width = 96
          Height = 26
          Caption = 'Hist'#243'rico'
          TabOrder = 26
          OnClick = btnProductHistoryClick
        end
      end
      object gridProducts: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 28
      end
    end
    object tsCustomers: TTabSheet
      Caption = 'Clientes'
      object pnlCustomers: TPanel
        Left = 0
        Top = 0
        Width = 900
        Height = 42
        Align = alTop
        BevelOuter = bvNone
        Caption = ''
        TabOrder = 34
        object edtCustomerSearch: TEdit
          Left = 8
          Top = 9
          Width = 200
          Height = 24
          TabOrder = 29
          Text = ''
        end
        object btnCustomerSearch: TButton
          Left = 216
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Buscar'
          TabOrder = 30
          OnClick = btnCustomerSearchClick
        end
        object btnCustomerNew: TButton
          Left = 312
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Novo'
          TabOrder = 31
          OnClick = btnCustomerNewClick
        end
        object btnCustomerEdit: TButton
          Left = 408
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Editar'
          TabOrder = 32
          OnClick = btnCustomerEditClick
        end
        object btnCustomerHistory: TButton
          Left = 504
          Top = 8
          Width = 96
          Height = 26
          Caption = 'Hist'#243'rico'
          TabOrder = 33
          OnClick = btnCustomerHistoryClick
        end
      end
      object gridCustomers: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 35
      end
    end
    object tsSuppliers: TTabSheet
      Caption = 'Fornecedores'
      object pnlSuppliers: TPanel
        Left = 0
        Top = 0
        Width = 900
        Height = 42
        Align = alTop
        BevelOuter = bvNone
        Caption = ''
        TabOrder = 38
        object btnSupplierNew: TButton
          Left = 8
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Novo'
          TabOrder = 36
          OnClick = btnSupplierNewClick
        end
        object btnSupplierEdit: TButton
          Left = 104
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Editar'
          TabOrder = 37
          OnClick = btnSupplierEditClick
        end
      end
      object gridSuppliers: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 39
      end
    end
    object tsCarriers: TTabSheet
      Caption = 'Transportadoras'
      object pnlCarriers: TPanel
        Left = 0
        Top = 0
        Width = 900
        Height = 42
        Align = alTop
        BevelOuter = bvNone
        Caption = ''
        TabOrder = 42
        object btnCarrierNew: TButton
          Left = 8
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Novo'
          TabOrder = 40
          OnClick = btnCarrierNewClick
        end
        object btnCarrierEdit: TButton
          Left = 104
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Editar'
          TabOrder = 41
          OnClick = btnCarrierEditClick
        end
      end
      object gridCarriers: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 43
      end
    end
    object tsWarehouses: TTabSheet
      Caption = 'Dep'#243'sitos'
      object pnlWarehouses: TPanel
        Left = 0
        Top = 0
        Width = 900
        Height = 42
        Align = alTop
        BevelOuter = bvNone
        Caption = ''
        TabOrder = 47
        object btnWarehouseNew: TButton
          Left = 8
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Novo'
          TabOrder = 44
          OnClick = btnWarehouseNewClick
        end
        object btnWarehouseEdit: TButton
          Left = 104
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Editar'
          TabOrder = 45
          OnClick = btnWarehouseEditClick
        end
        object btnLocationAdd: TButton
          Left = 200
          Top = 8
          Width = 128
          Height = 26
          Caption = 'Novo endere'#231'o'
          TabOrder = 46
          OnClick = btnLocationAddClick
        end
      end
      object gridLocations: TStringGrid
        Align = alBottom
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 48
        Height = 180
        Top = 380
        Left = 0
        Width = 900
      end
      object splWarehouses: TSplitter
        Left = 0
        Top = 374
        Width = 900
        Height = 6
        Cursor = crVSplit
        Align = alBottom
      end
      object gridWarehouses: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 49
        OnClick = gridWarehousesClick
      end
    end
    object tsUsers: TTabSheet
      Caption = 'Usu'#225'rios'
      object pnlUsers: TPanel
        Left = 0
        Top = 0
        Width = 900
        Height = 42
        Align = alTop
        BevelOuter = bvNone
        Caption = ''
        TabOrder = 51
        object btnUserNew: TButton
          Left = 8
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Novo'
          TabOrder = 50
          OnClick = btnUserNewClick
        end
      end
      object gridUsers: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 52
      end
    end
  end
end
