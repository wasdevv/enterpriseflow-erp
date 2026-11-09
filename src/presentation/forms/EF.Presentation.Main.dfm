object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'EnterpriseFlow ERP'
  ClientHeight = 680
  ClientWidth = 1100
  Menu = menuMain
  Position = poScreenCenter
  OnDestroy = FormDestroy
  object pcModules: TPageControl
    Left = 0
    Top = 0
    Width = 1100
    Height = 658
    Align = alClient
    TabOrder = 0
    OnChange = pcModulesChange
  end
  object sbStatus: TStatusBar
    Left = 0
    Top = 658
    Width = 1100
    Height = 22
    SimplePanel = True
  end
  object menuMain: TMainMenu
    Left = 16
    Top = 64
    object miFile: TMenuItem
      Caption = 'Sistema'
      object miPassword: TMenuItem
        Caption = 'Trocar senha'
        OnClick = miPasswordClick
      end
      object miExit: TMenuItem
        Caption = 'Sair'
        OnClick = miExitClick
      end
    end
  end
end
