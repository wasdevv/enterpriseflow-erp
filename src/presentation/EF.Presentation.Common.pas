unit EF.Presentation.Common;

{ Ajudantes de tela. Os formulários não têm SQL nem regra: pedem ao serviço e mostram a
  tabela que ele devolve. }

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, StdCtrls, Grids, Forms, Dialogs,
  EF.Application.Ports, EF.Infrastructure.Composition;

type
  { Base das abas do sistema. Sem DFM próprio: cada módulo traz o seu. }
  TModuleFrame = class(TFrame)
  protected
    FApp: TAppServices;
  public
    procedure Bind(const AApp: TAppServices); virtual;
    procedure Reload; virtual;
  end;

procedure FillGrid(const AGrid: TStringGrid; const ATable: TDataTable);
function GridCell(const AGrid: TStringGrid; const AColumn: string): string;
{ Id da linha selecionada; zero se a grade está vazia. }
function GridId(const AGrid: TStringGrid; const AColumn: string = 'ID'): Int64;
function RequireGridId(const AGrid: TStringGrid; const AWhat: string; const AColumn: string = 'ID'): Int64;
procedure FillCombo(const ACombo: TComboBox; const ATable: TDataTable; const AIdColumn, ATextColumn: string; const AAddEmpty: Boolean = False);
function ComboId(const ACombo: TComboBox): Int64;
procedure SelectComboId(const ACombo: TComboBox; const AId: Int64);
procedure ShowDomainMessage(const AMessage: string);
function AskRequiredText(const ATitle, APrompt: string; out AValue: string): Boolean;

type
  TDomainMessageSink = procedure(const AMessage: string) of object;

var
  { Com valor, recebe a mensagem em vez da caixa de diálogo: o teste de tela usa isso, pois
    uma caixa modal nativa travaria a execução automatizada. }
  DomainMessageSink: TDomainMessageSink = nil;

implementation

uses
  EF.Domain.Exceptions, EF.Presentation.Fields;

const
  CHiddenColumns: array [0 .. 2] of string = ('ID', 'PRODUCT_ID', 'WAREHOUSE_ID');

procedure TModuleFrame.Bind(const AApp: TAppServices);
begin
  FApp := AApp;
end;

procedure TModuleFrame.Reload;
begin
end;

function IsHiddenColumn(const AName: string): Boolean;
var
  LIndex: Integer;
begin
  for LIndex := Low(CHiddenColumns) to High(CHiddenColumns) do
    if SameText(CHiddenColumns[LIndex], AName) then
      Exit(True);
  Result := False;
end;

procedure FillGrid(const AGrid: TStringGrid; const ATable: TDataTable);
var
  LColumn, LRow, LWidth, LLongest: Integer;
begin
  AGrid.ColCount := Length(ATable.Columns) + 1;
  { A VCL recusa FixedRows >= RowCount: grade vazia ainda tem uma linha em branco. }
  if Length(ATable.Rows) = 0 then
    AGrid.RowCount := 2
  else
    AGrid.RowCount := Length(ATable.Rows) + 1;
  AGrid.FixedRows := 1;
  AGrid.FixedCols := 1;
  AGrid.ColWidths[0] := 12;
  for LColumn := 0 to High(ATable.Columns) do
  begin
    AGrid.Cells[LColumn + 1, 0] := ATable.Columns[LColumn];
    LLongest := Length(ATable.Columns[LColumn]);
    for LRow := 0 to High(ATable.Rows) do
    begin
      AGrid.Cells[LColumn + 1, LRow + 1] := ATable.Rows[LRow][LColumn];
      if Length(ATable.Rows[LRow][LColumn]) > LLongest then
        LLongest := Length(ATable.Rows[LRow][LColumn]);
    end;
    if IsHiddenColumn(ATable.Columns[LColumn]) then
      LWidth := 0
    else
    begin
      LWidth := LLongest * 8 + 16;
      if LWidth > 360 then
        LWidth := 360;
    end;
    AGrid.ColWidths[LColumn + 1] := LWidth;
  end;
  if Length(ATable.Rows) = 0 then
    for LColumn := 1 to AGrid.ColCount - 1 do
      AGrid.Cells[LColumn, 1] := '';
end;

function GridCell(const AGrid: TStringGrid; const AColumn: string): string;
var
  LColumn: Integer;
begin
  Result := '';
  if AGrid.Row < 1 then
    Exit;
  for LColumn := 1 to AGrid.ColCount - 1 do
    if SameText(AGrid.Cells[LColumn, 0], AColumn) then
      Exit(AGrid.Cells[LColumn, AGrid.Row]);
end;

function GridId(const AGrid: TStringGrid; const AColumn: string): Int64;
begin
  Result := StrToInt64Def(GridCell(AGrid, AColumn), 0);
end;

function RequireGridId(const AGrid: TStringGrid; const AWhat: string; const AColumn: string): Int64;
begin
  Result := GridId(AGrid, AColumn);
  if Result = 0 then
    raise EValidationError.CreateFmt('Selecione %s na lista.', [AWhat]);
end;

procedure FillCombo(const ACombo: TComboBox; const ATable: TDataTable; const AIdColumn, ATextColumn: string; const AAddEmpty: Boolean);
var
  LRow: Integer;
begin
  ACombo.Items.BeginUpdate;
  try
    ACombo.Items.Clear;
    if AAddEmpty then
      ACombo.Items.AddObject('', TObject(NativeInt(0)));
    for LRow := 0 to High(ATable.Rows) do
      ACombo.Items.AddObject(ATable.Cell(LRow, ATextColumn), TObject(NativeInt(StrToInt64Def(ATable.Cell(LRow, AIdColumn), 0))));
  finally
    ACombo.Items.EndUpdate;
  end;
  if ACombo.Items.Count > 0 then
    ACombo.ItemIndex := 0;
end;

function ComboId(const ACombo: TComboBox): Int64;
begin
  if ACombo.ItemIndex < 0 then
    Result := 0
  else
    Result := NativeInt(ACombo.Items.Objects[ACombo.ItemIndex]);
end;

procedure SelectComboId(const ACombo: TComboBox; const AId: Int64);
var
  LIndex: Integer;
begin
  for LIndex := 0 to ACombo.Items.Count - 1 do
    if NativeInt(ACombo.Items.Objects[LIndex]) = AId then
    begin
      ACombo.ItemIndex := LIndex;
      Exit;
    end;
end;

procedure ShowDomainMessage(const AMessage: string);
begin
  if Assigned(DomainMessageSink) then
    DomainMessageSink(AMessage)
  else
    MessageDlg(AMessage, mtWarning, [mbOK], 0);
end;

function AskRequiredText(const ATitle, APrompt: string; out AValue: string): Boolean;
var
  LDialog: TFieldsDialog;
begin
  AValue := '';
  LDialog := TFieldsDialog.CreateDialog(nil, ATitle);
  try
    LDialog.AddText('value', APrompt, '');
    Result := LDialog.Execute;
    if Result then
    begin
      AValue := LDialog.Text('value');
      Result := AValue <> '';
    end;
  finally
    LDialog.Free;
  end;
end;

end.
