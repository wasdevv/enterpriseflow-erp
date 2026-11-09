program race_worker;

{ Processo independente que tenta confirmar um pedido num instante combinado.
  Exit: 0 = reservou, 10 = estoque insuficiente, 1 = outro erro. }

{$APPTYPE CONSOLE}
{$I EF.inc}

uses
  {$IFDEF FPC}{$IFDEF UNIX}cthreads, cwstring,{$ENDIF}{$ENDIF}
  SysUtils, DateUtils,
  EF.Application.Ports, EF.Application.Sales,
  EF.Domain.Quantity, EF.Domain.Exceptions,
  EF.Infrastructure.Config, EF.Infrastructure.Database, EF.Infrastructure.Database.Driver,
  EF.Infrastructure.Composition, EF.Infrastructure.UnitOfWork, EF.Shared.Logging, EF.Shared.Text;

var
  LConfig: TDbConfig;
  LCtx: TUserContext;
  LApp: TAppServices;
  LCommand: TNewOrderCommand;
  LStartAt: Int64;
begin
  try
    if not DbConfigFromEnvironment('EF_TEST_DB', LConfig) then
      raise Exception.Create('EF_TEST_DB_* não configurado');
    LCtx.UserId := StrToInt64(ParamStr(1));
    LCtx.Username := 'race';
    SetLength(LCtx.Permissions, 1);
    LCtx.Permissions[0] := PermOrderConfirm;
    LCtx.CorrelationId := NewCorrelationId;
    LCommand.CustomerId := StrToInt64(ParamStr(2));
    LCommand.CarrierId := 0;
    SetLength(LCommand.Lines, 1);
    LCommand.Lines[0].ProductId := StrToInt64(ParamStr(3));
    LCommand.Lines[0].WarehouseId := StrToInt64(ParamStr(4));
    LCommand.Lines[0].Quantity := TQuantity.FromUnits(1);
    LCommand.Installments := 1;
    LCommand.IntervalDays := 30;
    LCommand.IdempotencyKey := NewCorrelationId;
    LStartAt := StrToInt64(ParamStr(5));

    LApp := TAppServices.Create(OpenSession(LConfig), LCtx, TSystemClock.Create, TNullLogger.Create);
    try
      { Já conectado: espera o instante combinado para os processos colidirem no SQL. }
      while MilliSecondsBetween(EncodeDate(1970, 1, 1), Now) < LStartAt do
        Sleep(1);
      LApp.Sales.ConfirmNew(LCommand);
    finally
      LApp.Free;
    end;
    Halt(0);
  except
    on EInsufficientStock do
      Halt(10);
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
