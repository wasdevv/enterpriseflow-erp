object IntegrationFrame: TIntegrationFrame
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
    TabOrder = 93
    object btnRefresh: TButton
      Left = 8
      Top = 8
      Width = 96
      Height = 26
      Caption = 'Atualizar'
      TabOrder = 90
      OnClick = btnRefreshClick
    end
    object btnProcess: TButton
      Left = 110
      Top = 8
      Width = 144
      Height = 26
      Caption = 'Processar agora'
      TabOrder = 91
      OnClick = btnProcessClick
    end
    object btnRequeue: TButton
      Left = 260
      Top = 8
      Width = 176
      Height = 26
      Caption = 'Reenfileirar evento'
      TabOrder = 92
      OnClick = btnRequeueClick
    end
  end
  object pcIntegration: TPageControl
    Left = 0
    Top = 0
    Width = 900
    Height = 600
    ActivePage = tsOutbox
    Align = alClient
    TabOrder = 98
    object tsOutbox: TTabSheet
      Caption = 'Outbox'
      object gridOutbox: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 94
      end
    end
    object tsLogs: TTabSheet
      Caption = 'Log de integra'#231#227'o'
      object gridLogs: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 95
      end
    end
    object tsMetrics: TTabSheet
      Caption = 'M'#233'tricas'
      object gridMetrics: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 96
      end
    end
    object tsAudit: TTabSheet
      Caption = 'Auditoria'
      object gridAudit: TStringGrid
        Align = alClient
        ColCount = 2
        DefaultRowHeight = 22
        FixedCols = 1
        RowCount = 2
        FixedRows = 1
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
        TabOrder = 97
      end
    end
  end
end
