object PurchasesFrame: TPurchasesFrame
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
    TabOrder = 69
    object btnNew: TButton
      Left = 8
      Top = 8
      Width = 192
      Height = 26
      Caption = 'Novo pedido de compra'
      TabOrder = 66
      OnClick = btnNewClick
    end
    object btnReceive: TButton
      Left = 206
      Top = 8
      Width = 90
      Height = 26
      Caption = 'Receber'
      TabOrder = 67
      OnClick = btnReceiveClick
    end
    object btnCloseShort: TButton
      Left = 302
      Top = 8
      Width = 168
      Height = 26
      Caption = 'Encerrar com falta'
      TabOrder = 68
      OnClick = btnCloseShortClick
    end
  end
  object gridItems: TStringGrid
    Align = alBottom
    ColCount = 2
    DefaultRowHeight = 22
    FixedCols = 1
    RowCount = 2
    FixedRows = 1
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
    TabOrder = 70
    Height = 210
    Top = 390
    Left = 0
    Width = 900
  end
  object splItems: TSplitter
    Left = 0
    Top = 384
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
    TabOrder = 71
    OnClick = gridOrdersClick
  end
end
