unit EF.Presentation.TableView;

{ Janela de consulta: mostra uma tabela e exporta CSV. Usada para histórico e auditoria. }

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Grids, Dialogs,
  EF.Application.Ports;

type
  TTableViewForm = class(TForm)
    pnlButtons: TPanel;
    btnExport: TButton;
    btnClose: TButton;
    grid: TStringGrid;
    dlgSave: TSaveDialog;
    procedure btnExportClick(Sender: TObject);
  private
    FTable: TDataTable;
  public
    class procedure ShowTable(const AOwner: TComponent; const ATitle: string; const ATable: TDataTable);
  end;

implementation

{$R *.dfm}

uses
  EF.Presentation.Common, EF.Infrastructure.Reporting;

class procedure TTableViewForm.ShowTable(const AOwner: TComponent; const ATitle: string; const ATable: TDataTable);
var
  LForm: TTableViewForm;
begin
  LForm := TTableViewForm.Create(AOwner);
  try
    LForm.Caption := ATitle;
    LForm.FTable := ATable;
    FillGrid(LForm.grid, ATable);
    LForm.ShowModal;
  finally
    LForm.Free;
  end;
end;

procedure TTableViewForm.btnExportClick(Sender: TObject);
begin
  if dlgSave.Execute then
    SaveDataTableCsv(FTable, dlgSave.FileName);
end;

end.
