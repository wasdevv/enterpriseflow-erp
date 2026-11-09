object LinesForm: TLinesForm
  Left = 0
  Top = 0
  Caption = 'Pedido'
  ClientHeight = 540
  ClientWidth = 860
  Position = poScreenCenter
  object pnlHeader: TPanel
    Left = 0
    Top = 0
    Width = 860
    Height = 84
    Align = alTop
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 0
    object lblParty: TLabel
      Left = 10
      Top = 12
      Width = 49
      Height = 16
      Caption = 'Cliente'
    end
    object cbParty: TComboBox
      Left = 120
      Top = 8
      Width = 300
      Height = 24
      Style = csDropDownList
      TabOrder = 6
    end
    object lblWarehouse: TLabel
      Left = 440
      Top = 12
      Width = 56
      Height = 16
      Caption = 'Dep'#243'sito'
    end
    object cbWarehouse: TComboBox
      Left = 510
      Top = 8
      Width = 170
      Height = 24
      Style = csDropDownList
      TabOrder = 7
    end
    object lblCarrier: TLabel
      Left = 10
      Top = 48
      Width = 98
      Height = 16
      Caption = 'Transportadora'
    end
    object cbCarrier: TComboBox
      Left = 120
      Top = 44
      Width = 300
      Height = 24
      Style = csDropDownList
      TabOrder = 8
    end
    object lblInstallments: TLabel
      Left = 440
      Top = 48
      Width = 56
      Height = 16
      Caption = 'Parcelas'
    end
    object edtInstallments: TEdit
      Left = 510
      Top = 44
      Width = 50
      Height = 24
      TabOrder = 9
      Text = '1'
    end
    object lblInterval: TLabel
      Left = 575
      Top = 48
      Width = 112
      Height = 16
      Caption = 'Intervalo (dias)'
    end
    object edtInterval: TEdit
      Left = 690
      Top = 44
      Width = 50
      Height = 24
      TabOrder = 10
      Text = '30'
    end
  end
  object pnlAdd: TPanel
    Left = 0
    Top = 84
    Width = 860
    Height = 84
    Align = alTop
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 1
    object lblSearch: TLabel
      Left = 10
      Top = 12
      Width = 42
      Height = 16
      Caption = 'Buscar'
    end
    object edtSearch: TEdit
      Left = 120
      Top = 8
      Width = 170
      Height = 24
      TabOrder = 11
      Text = ''
    end
    object btnSearch: TButton
      Left = 298
      Top = 7
      Width = 80
      Height = 26
      Caption = 'Buscar'
      TabOrder = 12
      OnClick = btnSearchClick
    end
    object cbProduct: TComboBox
      Left = 390
      Top = 8
      Width = 460
      Height = 24
      Style = csDropDownList
      TabOrder = 13
    end
    object lblQuantity: TLabel
      Left = 10
      Top = 48
      Width = 70
      Height = 16
      Caption = 'Quantidade'
    end
    object edtQuantity: TEdit
      Left = 120
      Top = 44
      Width = 90
      Height = 24
      TabOrder = 14
      Text = ''
    end
    object lblCost: TLabel
      Left = 225
      Top = 48
      Width = 35
      Height = 16
      Caption = 'Custo'
    end
    object edtCost: TEdit
      Left = 270
      Top = 44
      Width = 90
      Height = 24
      TabOrder = 15
      Text = ''
    end
    object btnAdd: TButton
      Left = 390
      Top = 43
      Width = 120
      Height = 26
      Caption = 'Adicionar item'
      TabOrder = 16
      OnClick = btnAddClick
    end
    object btnRemove: TButton
      Left = 518
      Top = 43
      Width = 120
      Height = 26
      Caption = 'Remover item'
      TabOrder = 17
      OnClick = btnRemoveClick
    end
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 496
    Width = 860
    Height = 44
    Align = alBottom
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 3
    object btnPrimary: TButton
      Left = 380
      Top = 8
      Width = 170
      Height = 28
      Caption = 'Confirmar'
      TabOrder = 18
      OnClick = btnPrimaryClick
    end
    object btnSecondary: TButton
      Left = 556
      Top = 8
      Width = 150
      Height = 28
      Caption = 'Salvar'
      TabOrder = 19
      OnClick = btnSecondaryClick
    end
    object btnCancel: TButton
      Left = 712
      Top = 8
      Width = 130
      Height = 28
      Cancel = True
      Caption = 'Cancelar'
      ModalResult = 2
      TabOrder = 20
    end
  end
  object gridLines: TStringGrid
    Align = alClient
    ColCount = 2
    DefaultRowHeight = 22
    FixedCols = 1
    RowCount = 2
    FixedRows = 1
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect]
    TabOrder = 21
  end
end
