object TableViewForm: TTableViewForm
  Left = 0
  Top = 0
  Caption = 'Consulta'
  ClientHeight = 480
  ClientWidth = 860
  Position = poScreenCenter
  object pnlButtons: TPanel
    Left = 0
    Top = 436
    Width = 860
    Height = 44
    Align = alBottom
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 1
    object btnExport: TButton
      Left = 8
      Top = 8
      Width = 120
      Height = 26
      Caption = 'Exportar CSV'
      TabOrder = 3
      OnClick = btnExportClick
    end
    object btnClose: TButton
      Left = 140
      Top = 8
      Width = 90
      Height = 26
      Caption = 'Fechar'
      TabOrder = 4
      Cancel = True
      ModalResult = 2
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
    TabOrder = 5
  end
  object dlgSave: TSaveDialog
    DefaultExt = 'csv'
    Filter = 'CSV (*.csv)|*.csv'
    Left = 16
    Top = 64
  end
end
