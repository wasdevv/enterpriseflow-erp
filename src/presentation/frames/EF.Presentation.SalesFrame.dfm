object SalesFrame: TSalesFrame
  Left = 0
  Top = 0
  Width = 900
  Height = 600
  TabOrder = 0
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 900
    Height = 42
    Align = alTop
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 79
    object lblStatus: TLabel
      Left = 8
      Top = 13
      Width = 42
      Height = 16
      Caption = 'Status'
    end
    object cbStatus: TComboBox
      Left = 56
      Top = 9
      Width = 130
      Height = 24
      Style = csDropDownList
      TabOrder = 72
      OnChange = cbStatusChange
    end
    object btnNew: TButton
      Left = 194
      Top = 8
      Width = 112
      Height = 26
      Caption = 'Novo pedido'
      TabOrder = 73
      OnClick = btnNewClick
    end
    object btnConfirm: TButton
      Left = 312
      Top = 8
      Width = 176
      Height = 26
      Caption = 'Confirmar or'#231'amento'
      TabOrder = 74
      OnClick = btnConfirmClick
    end
    object btnPick: TButton
      Left = 494
      Top = 8
      Width = 160
      Height = 26
      Caption = 'Iniciar separa'#231#227'o'
      TabOrder = 75
      OnClick = btnPickClick
    end
    object btnShip: TButton
      Left = 660
      Top = 8
      Width = 90
      Height = 26
      Caption = 'Expedir'
      TabOrder = 76
      OnClick = btnShipClick
    end
    object btnInvoice: TButton
      Left = 756
      Top = 8
      Width = 90
      Height = 26
      Caption = 'Faturar'
      TabOrder = 77
      OnClick = btnInvoiceClick
    end
    object btnCancelOrder: TButton
      Left = 852
      Top = 8
      Width = 144
      Height = 26
      Caption = 'Cancelar pedido'
      TabOrder = 78
      OnClick = btnCancelOrderClick
    end
  end
  object pcDetail: TPageControl
    Left = 0
    Top = 380
    Width = 900
    Height = 220
    ActivePage = tsItems
    Align = alBottom
    TabOrder = 82
    object tsItems: TTabSheet
      Caption = 'Itens'
      object gridItems: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 80
      end
    end
    object tsHistory: TTabSheet
      Caption = 'Hist'#243'rico de status'
      object gridHistory: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 81
      end
    end
  end
  object splDetail: TSplitter
    Left = 0
    Top = 374
    Width = 900
    Height = 6
    Cursor = crVSplit
    Align = alBottom
  end
  object gridOrders: TStringGrid
    Align = alClient
    ColCount = 2
    DefaultRowHeight = 22
    FixedCols = 1
    RowCount = 2
    FixedRows = 1
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
    TabOrder = 83
    OnClick = gridOrdersClick
  end
end
