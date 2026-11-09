unit EF.Presentation.IntegrationFrame;

{$I EF.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Grids, ComCtrls,
  EF.Application.Ports, EF.Presentation.Common;

type
  TIntegrationFrame = class(TModuleFrame)
    pnlTop: TPanel;
    btnRefresh: TButton;
    btnProcess: TButton;
    btnRequeue: TButton;
    pcIntegration: TPageControl;
    tsOutbox: TTabSheet;
    gridOutbox: TStringGrid;
    tsLogs: TTabSheet;
    gridLogs: TStringGrid;
    tsMetrics: TTabSheet;
    gridMetrics: TStringGrid;
    tsAudit: TTabSheet;
    gridAudit: TStringGrid;
    procedure btnRefreshClick(Sender: TObject);
    procedure btnProcessClick(Sender: TObject);
    procedure btnRequeueClick(Sender: TObject);
  private
    FWake: TNotifyEvent;
  public
    procedure Reload; override;
    { Acorda o worker em segundo plano, que tem conexão própria. }
    property OnWakeWorker: TNotifyEvent read FWake write FWake;
  end;

implementation

{$R *.dfm}

uses
  EF.Application.Outbox, EF.Infrastructure.Http;

procedure TIntegrationFrame.Reload;
begin
  FillGrid(gridOutbox, FApp.ReadModel.OutboxQueue);
  FillGrid(gridLogs, FApp.ReadModel.IntegrationLog);
  FillGrid(gridMetrics, FApp.ReadModel.MetricsSummary);
  FillGrid(gridAudit, FApp.ReadModel.AuditTrail('', 0));
  btnRequeue.Enabled := FApp.Context.Has(PermIntegrationManage);
end;

procedure TIntegrationFrame.btnRefreshClick(Sender: TObject);
begin
  Reload;
end;

procedure TIntegrationFrame.btnProcessClick(Sender: TObject);
begin
  if Assigned(FWake) then
    FWake(Self);
end;

procedure TIntegrationFrame.btnRequeueClick(Sender: TObject);
var
  LWorker: TOutboxWorker;
begin
  LWorker := FApp.NewOutboxWorker(nil);
  try
    LWorker.Requeue(RequireGridId(gridOutbox, 'um evento'));
  finally
    LWorker.Free;
  end;
  Reload;
end;

end.
