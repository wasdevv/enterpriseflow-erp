object FinanceFrame: TFinanceFrame
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
    TabOrder = 87
    object chkOverdue: TCheckBox
      Left = 8
      Top = 12
      Width = 130
      Height = 20
      Caption = 'S'#243' vencidos'
      TabOrder = 84
      OnClick = chkOverdueClick
    end
    object btnSettle: TButton
      Left = 146
      Top = 8
      Width = 152
      Height = 26
      Caption = 'Liquidar parcela'
      TabOrder = 85
      OnClick = btnSettleClick
    end
    object btnReverse: TButton
      Left = 304
      Top = 8
      Width = 176
      Height = 26
      Caption = 'Estornar liquida'#231#227'o'
      TabOrder = 86
      OnClick = btnReverseClick
    end
  end
  object gridSettlements: TStringGrid
    Align = alBottom
    ColCount = 2
    DefaultRowHeight = 22
    FixedCols = 1
    RowCount = 2
    FixedRows = 1
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
    TabOrder = 88
    Height = 200
    Top = 400
    Left = 0
    Width = 900
  end
  object splSettlements: TSplitter
    Left = 0
    Top = 394
    Width = 900
    Height = 6
    Cursor = crVSplit
    Align = alBottom
  end
  object gridInstallments: TStringGrid
    Align = alClient
    ColCount = 2
    DefaultRowHeight = 22
    FixedCols = 1
    RowCount = 2
    FixedRows = 1
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
    TabOrder = 89
    OnClick = gridInstallmentsClick
  end
end
