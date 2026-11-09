object ReportsFrame: TReportsFrame
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
    TabOrder = 104
    object cbReport: TComboBox
      Left = 8
      Top = 9
      Width = 280
      Height = 24
      Style = csDropDownList
      TabOrder = 99
    end
    object lblFrom: TLabel
      Left = 300
      Top = 13
      Width = 14
      Height = 16
      Caption = 'De'
    end
    object edtFrom: TEdit
      Left = 322
      Top = 9
      Width = 95
      Height = 24
      TabOrder = 100
      Text = ''
    end
    object lblTo: TLabel
      Left = 426
      Top = 13
      Width = 21
      Height = 16
      Caption = 'At'#233
    end
    object edtTo: TEdit
      Left = 454
      Top = 9
      Width = 95
      Height = 24
      TabOrder = 101
      Text = ''
    end
    object btnRun: TButton
      Left = 557
      Top = 8
      Width = 90
      Height = 26
      Caption = 'Gerar'
      TabOrder = 102
      OnClick = btnRunClick
    end
    object btnExport: TButton
      Left = 653
      Top = 8
      Width = 120
      Height = 26
      Caption = 'Exportar CSV'
      TabOrder = 103
      OnClick = btnExportClick
    end
  end
  object grid: TStringGrid
    Align = alClient
    ColCount = 2
    DefaultRowHeight = 22
    FixedCols = 1
    RowCount = 2
    FixedRows = 1
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
    TabOrder = 105
  end
  object dlgSave: TSaveDialog
    DefaultExt = 'csv'
    Filter = 'CSV (*.csv)|*.csv'
    Left = 16
    Top = 64
  end
end
