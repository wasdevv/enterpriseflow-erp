program EnterpriseFlow;

{ Aplicação VCL. Monte com EnterpriseFlow.dproj (Delphi). As mesmas telas são verificadas com a
  LCL em tools/fpc/EnterpriseFlowLcl.lpr, porque o CI não tem licença de Delphi. }

uses
  Vcl.Forms,
  EF.Application.Ports in 'src\application\EF.Application.Ports.pas',
  EF.Application.Base in 'src\application\services\EF.Application.Base.pas',
  EF.Application.Catalog in 'src\application\services\EF.Application.Catalog.pas',
  EF.Application.Finance in 'src\application\services\EF.Application.Finance.pas',
  EF.Application.Inventory in 'src\application\services\EF.Application.Inventory.pas',
  EF.Application.Outbox in 'src\application\services\EF.Application.Outbox.pas',
  EF.Application.Sales in 'src\application\services\EF.Application.Sales.pas',
  EF.Application.StockLedger in 'src\application\services\EF.Application.StockLedger.pas',
  EF.Domain.Receivables in 'src\domain\entities\EF.Domain.Receivables.pas',
  EF.Domain.Stock in 'src\domain\entities\EF.Domain.Stock.pas',
  EF.Domain.Exceptions in 'src\domain\exceptions\EF.Domain.Exceptions.pas',
  EF.Domain.OrderState in 'src\domain\rules\EF.Domain.OrderState.pas',
  EF.Domain.Policies in 'src\domain\rules\EF.Domain.Policies.pas',
  EF.Domain.Money in 'src\domain\valueobjects\EF.Domain.Money.pas',
  EF.Domain.Quantity in 'src\domain\valueobjects\EF.Domain.Quantity.pas',
  EF.Infrastructure.Composition in 'src\infrastructure\EF.Infrastructure.Composition.pas',
  EF.Infrastructure.Config in 'src\infrastructure\EF.Infrastructure.Config.pas',
  EF.Infrastructure.OutboxThread in 'src\infrastructure\EF.Infrastructure.OutboxThread.pas',
  EF.Infrastructure.Database.Driver in 'src\infrastructure\database\EF.Infrastructure.Database.Driver.pas',
  EF.Infrastructure.Database.FireDAC in 'src\infrastructure\database\EF.Infrastructure.Database.FireDAC.pas',
  EF.Infrastructure.Database.Migrator in 'src\infrastructure\database\EF.Infrastructure.Database.Migrator.pas',
  EF.Infrastructure.Database in 'src\infrastructure\database\EF.Infrastructure.Database.pas',
  EF.Infrastructure.Http.Net in 'src\infrastructure\integrations\EF.Infrastructure.Http.Net.pas',
  EF.Infrastructure.Http in 'src\infrastructure\integrations\EF.Infrastructure.Http.pas',
  EF.Infrastructure.Reporting in 'src\infrastructure\reporting\EF.Infrastructure.Reporting.pas',
  EF.Infrastructure.Repositories.Sales in 'src\infrastructure\repositories\EF.Infrastructure.Repositories.Sales.pas',
  EF.Infrastructure.Repositories.Stock in 'src\infrastructure\repositories\EF.Infrastructure.Repositories.Stock.pas',
  EF.Infrastructure.Repositories.Support in 'src\infrastructure\repositories\EF.Infrastructure.Repositories.Support.pas',
  EF.Infrastructure.UnitOfWork in 'src\infrastructure\repositories\EF.Infrastructure.UnitOfWork.pas',
  EF.Presentation.Bootstrap in 'src\presentation\EF.Presentation.Bootstrap.pas',
  EF.Presentation.Common in 'src\presentation\EF.Presentation.Common.pas',
  EF.Presentation.Fields in 'src\presentation\forms\EF.Presentation.Fields.pas' {FieldsDialog},
  EF.Presentation.Lines in 'src\presentation\forms\EF.Presentation.Lines.pas' {LinesForm},
  EF.Presentation.Login in 'src\presentation\forms\EF.Presentation.Login.pas' {LoginForm},
  EF.Presentation.Main in 'src\presentation\forms\EF.Presentation.Main.pas' {MainForm},
  EF.Presentation.TableView in 'src\presentation\forms\EF.Presentation.TableView.pas' {TableViewForm},
  EF.Presentation.CatalogFrame in 'src\presentation\frames\EF.Presentation.CatalogFrame.pas' {CatalogFrame: TFrame},
  EF.Presentation.FinanceFrame in 'src\presentation\frames\EF.Presentation.FinanceFrame.pas' {FinanceFrame: TFrame},
  EF.Presentation.IntegrationFrame in 'src\presentation\frames\EF.Presentation.IntegrationFrame.pas' {IntegrationFrame: TFrame},
  EF.Presentation.PurchasesFrame in 'src\presentation\frames\EF.Presentation.PurchasesFrame.pas' {PurchasesFrame: TFrame},
  EF.Presentation.ReportsFrame in 'src\presentation\frames\EF.Presentation.ReportsFrame.pas' {ReportsFrame: TFrame},
  EF.Presentation.SalesFrame in 'src\presentation\frames\EF.Presentation.SalesFrame.pas' {SalesFrame: TFrame},
  EF.Presentation.StockFrame in 'src\presentation\frames\EF.Presentation.StockFrame.pas' {StockFrame: TFrame},
  EF.Shared.Crypto in 'src\shared\EF.Shared.Crypto.pas',
  EF.Shared.Text in 'src\shared\EF.Shared.Text.pas',
  EF.Shared.Logging in 'src\shared\logging\EF.Shared.Logging.pas',
  EF.Shared.Documents in 'src\shared\validation\EF.Shared.Documents.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'EnterpriseFlow ERP';
  RunApplication;
end.
