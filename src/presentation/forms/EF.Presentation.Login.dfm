object LoginForm: TLoginForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'EnterpriseFlow ERP'
  ClientHeight = 270
  ClientWidth = 380
  Position = poScreenCenter
  object lblTitle: TLabel
    Left = 24
    Top = 14
    Width = 250
    Height = 24
    Caption = 'EnterpriseFlow ERP'
    ParentFont = False
    Font.Height = -18
    Font.Style = [fsBold]
  end
  object lblSubtitle: TLabel
    Left = 24
    Top = 46
    Width = 330
    Height = 16
    Caption = 'Distribuidora S'#227'o Lucas: cen'#225'rio fict'#237'cio de portf'#243'lio'
  end
  object lblUser: TLabel
    Left = 24
    Top = 80
    Width = 49
    Height = 16
    Caption = 'Usu'#225'rio'
  end
  object edtUser: TEdit
    Left = 24
    Top = 100
    Width = 330
    Height = 24
    TabOrder = 0
    Text = ''
  end
  object lblPassword: TLabel
    Left = 24
    Top = 132
    Width = 35
    Height = 16
    Caption = 'Senha'
  end
  object edtPassword: TEdit
    Left = 24
    Top = 152
    Width = 330
    Height = 24
    PasswordChar = '*'
    TabOrder = 1
    Text = ''
  end
  object lblError: TLabel
    Left = 24
    Top = 184
    Width = 330
    Height = 16
    Caption = ''
    ParentFont = False
    Font.Color = clRed
  end
  object btnLogin: TButton
    Left = 158
    Top = 224
    Width = 95
    Height = 28
    Caption = 'Entrar'
    Default = True
    TabOrder = 2
    OnClick = btnLoginClick
  end
  object btnCancel: TButton
    Left = 259
    Top = 224
    Width = 95
    Height = 28
    Cancel = True
    Caption = 'Sair'
    ModalResult = 2
    TabOrder = 3
  end
end
