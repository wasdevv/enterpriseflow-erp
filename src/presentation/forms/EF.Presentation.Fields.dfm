object FieldsDialog: TFieldsDialog
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Campos'
  ClientHeight = 240
  ClientWidth = 560
  Position = poScreenCenter
  OnDestroy = FormDestroy
  object pnlButtons: TPanel
    Left = 0
    Top = 196
    Width = 560
    Height = 44
    Align = alBottom
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 1
    object btnOk: TButton
      Left = 350
      Top = 8
      Width = 95
      Height = 26
      Caption = 'Salvar'
      TabOrder = 1
      Default = True
      ModalResult = 1
    end
    object btnCancel: TButton
      Left = 455
      Top = 8
      Width = 95
      Height = 26
      Caption = 'Cancelar'
      TabOrder = 2
      Cancel = True
      ModalResult = 2
    end
  end
  object pnlFields: TPanel
    Left = 0
    Top = 0
    Width = 560
    Height = 196
    Align = alClient
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 0
  end
end
