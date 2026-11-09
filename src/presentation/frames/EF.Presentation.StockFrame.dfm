object StockFrame: TStockFrame
  Left = 0
  Top = 0
  Width = 900
  Height = 600
  TabOrder = 0
  object pcStock: TPageControl
    Left = 0
    Top = 0
    Width = 900
    Height = 600
    ActivePage = tsBalances
    Align = alClient
    TabOrder = 65
    object tsBalances: TTabSheet
      Caption = 'Saldos e Kardex'
      object pnlBalances: TPanel
        Left = 0
        Top = 0
        Width = 900
        Height = 42
        Align = alTop
        BevelOuter = bvNone
        Caption = ''
        TabOrder = 58
        object edtSearch: TEdit
          Left = 8
          Top = 9
          Width = 200
          Height = 24
          TabOrder = 54
          Text = ''
        end
        object btnSearch: TButton
          Left = 216
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Buscar'
          TabOrder = 55
          OnClick = btnSearchClick
        end
        object btnTransfer: TButton
          Left = 312
          Top = 8
          Width = 104
          Height = 26
          Caption = 'Transferir'
          TabOrder = 56
          OnClick = btnTransferClick
        end
        object btnAdjust: TButton
          Left = 422
          Top = 8
          Width = 152
          Height = 26
          Caption = 'Solicitar ajuste'
          TabOrder = 57
          OnClick = btnAdjustClick
        end
      end
      object gridKardex: TStringGrid
        Align = alBottom
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 59
        Height = 210
        Top = 350
        Left = 0
        Width = 900
      end
      object splKardex: TSplitter
        Left = 0
        Top = 344
        Width = 900
        Height = 6
        Cursor = crVSplit
        Align = alBottom
      end
      object gridBalances: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 60
        OnClick = gridBalancesClick
      end
    end
    object tsAdjustments: TTabSheet
      Caption = 'Ajustes pendentes'
      object pnlAdjustments: TPanel
        Left = 0
        Top = 0
        Width = 900
        Height = 42
        Align = alTop
        BevelOuter = bvNone
        Caption = ''
        TabOrder = 63
        object btnApprove: TButton
          Left = 8
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Aprovar'
          TabOrder = 61
          OnClick = btnApproveClick
        end
        object btnReject: TButton
          Left = 104
          Top = 8
          Width = 90
          Height = 26
          Caption = 'Recusar'
          TabOrder = 62
          OnClick = btnRejectClick
        end
      end
      object gridAdjustments: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 64
      end
    end
  end
end
