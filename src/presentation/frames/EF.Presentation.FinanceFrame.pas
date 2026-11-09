unit EF.Presentation.FinanceFrame;

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Grids,
  EF.Application.Ports, EF.Presentation.Common;

type
  TFinanceFrame = class(TModuleFrame)
    pnlTop: TPanel;
    chkOverdue: TCheckBox;
    btnSettle: TButton;
    btnReverse: TButton;
    gridInstallments: TStringGrid;
    splSettlements: TSplitter;
    gridSettlements: TStringGrid;
    procedure chkOverdueClick(Sender: TObject);
    procedure gridInstallmentsClick(Sender: TObject);
    procedure btnSettleClick(Sender: TObject);
    procedure btnReverseClick(Sender: TObject);
  public
    procedure Reload; override;
  end;

implementation

{$R *.dfm}

uses
  EF.Domain.Exceptions, EF.Domain.Money, EF.Domain.Policies,
  EF.Application.Finance,
  EF.Presentation.Fields, EF.Shared.Text;

procedure TFinanceFrame.Reload;
begin
  FillGrid(gridInstallments, FApp.ReadModel.OpenInstallments(FApp.Clock.Today, chkOverdue.Checked));
  gridInstallmentsClick(nil);
  btnSettle.Enabled := FApp.Context.Has(PermReceivableSettle);
  btnReverse.Enabled := FApp.Context.Has(PermReceivableReverse);
end;

procedure TFinanceFrame.chkOverdueClick(Sender: TObject);
begin
  Reload;
end;

procedure TFinanceFrame.gridInstallmentsClick(Sender: TObject);
begin
  FillGrid(gridSettlements, FApp.ReadModel.Settlements(GridId(gridInstallments)));
end;

procedure TFinanceFrame.btnSettleClick(Sender: TObject);
var
  LInstallment: Int64;
  LDialog: TFieldsDialog;
  LCommand: TSettleCommand;
  LCharges: TLateCharges;
  LKey: string;
begin
  LInstallment := RequireGridId(gridInstallments, 'uma parcela');
  LCharges := FApp.Receivables.SuggestCharges(LInstallment, FApp.Clock.Today);
  LKey := NewCorrelationId;
  LDialog := TFieldsDialog.CreateDialog(Self, 'Liquidar parcela');
  try
    LDialog.AddText('paid_on', 'Pagamento (dd/mm/aaaa)', FormatDateTime('dd"/"mm"/"yyyy', FApp.Clock.Today));
    LDialog.AddText('principal', 'Valor abatido do saldo', GridCell(gridInstallments, 'Em aberto'));
    LDialog.AddText('interest', 'Juros', LCharges.Interest.ToDisplay);
    LDialog.AddText('penalty', 'Multa', LCharges.Penalty.ToDisplay);
    LDialog.AddText('discount', 'Desconto', TMoney.Zero.ToDisplay);
    LDialog.AddText('note', 'Observação', '');
    while LDialog.Execute do
      try
        LCommand.InstallmentId := LInstallment;
        LCommand.PaidOn := ParseBrazilianDate(LDialog.Text('paid_on'));
        LCommand.Principal := TMoney.Parse(LDialog.Text('principal'));
        LCommand.Interest := TMoney.Parse(LDialog.Text('interest'));
        LCommand.Penalty := TMoney.Parse(LDialog.Text('penalty'));
        LCommand.Discount := TMoney.Parse(LDialog.Text('discount'));
        LCommand.Note := LDialog.Text('note');
        LCommand.IdempotencyKey := LKey;
        FApp.Receivables.Settle(LCommand);
        Reload;
        Break;
      except
        on E: EDomainError do
          ShowDomainMessage(E.Message);
      end;
  finally
    LDialog.Free;
  end;
end;

procedure TFinanceFrame.btnReverseClick(Sender: TObject);
var
  LReason: string;
begin
  if AskRequiredText('Estornar liquidação', 'Motivo do estorno:', LReason) then
  begin
    FApp.Receivables.Reverse(RequireGridId(gridSettlements, 'uma liquidação'), LReason);
    Reload;
  end;
end;

end.
