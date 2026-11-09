unit EF.Domain.OrderState;

{$I EF.inc}

interface

uses
  SysUtils;

type
  TOrderStatus = (osDraft, osConfirmed, osReserved, osPicking, osShipped, osInvoiced, osCancelled);

  { Única fonte das transições de pedido. A interface nunca escolhe status: pede a ação
    ao serviço, e o serviço pergunta aqui. }
  TOrderStateMachine = class
  public
    class function CanTransition(const AFrom, ATo: TOrderStatus): Boolean; static;
    class procedure EnsureTransition(const AFrom, ATo: TOrderStatus); static;
    class function CanCancel(const AStatus: TOrderStatus): Boolean; static;
    class function ToCode(const AStatus: TOrderStatus): string; static;
    class function FromCode(const ACode: string): TOrderStatus; static;
    class function DisplayName(const AStatus: TOrderStatus): string; static;
  end;

implementation

uses
  EF.Domain.Exceptions;

const
  CCodes: array [TOrderStatus] of string = ('DRAFT', 'CONFIRMED', 'RESERVED', 'PICKING', 'SHIPPED', 'INVOICED', 'CANCELLED');
  CNames: array [TOrderStatus] of string = ('Orçamento', 'Confirmado', 'Reservado', 'Em separação', 'Expedido', 'Faturado', 'Cancelado');

class function TOrderStateMachine.CanTransition(const AFrom, ATo: TOrderStatus): Boolean;
begin
  case AFrom of
    osDraft: Result := ATo in [osConfirmed, osCancelled];
    osConfirmed: Result := ATo in [osReserved, osCancelled];
    osReserved: Result := ATo in [osPicking, osCancelled];
    osPicking: Result := ATo = osShipped;
    osShipped: Result := ATo = osInvoiced;
  else
    Result := False;
  end;
end;

class procedure TOrderStateMachine.EnsureTransition(const AFrom, ATo: TOrderStatus);
begin
  if not CanTransition(AFrom, ATo) then
    raise EInvalidTransition.CreateFmt('Pedido em "%s" não pode passar para "%s".', [DisplayName(AFrom), DisplayName(ATo)]);
end;

class function TOrderStateMachine.CanCancel(const AStatus: TOrderStatus): Boolean;
begin
  Result := CanTransition(AStatus, osCancelled);
end;

class function TOrderStateMachine.ToCode(const AStatus: TOrderStatus): string;
begin
  Result := CCodes[AStatus];
end;

class function TOrderStateMachine.FromCode(const ACode: string): TOrderStatus;
var
  LStatus: TOrderStatus;
begin
  for LStatus := Low(TOrderStatus) to High(TOrderStatus) do
    if CCodes[LStatus] = ACode then
      Exit(LStatus);
  raise EValidationError.CreateFmt('Status de pedido desconhecido: "%s".', [ACode]);
end;

class function TOrderStateMachine.DisplayName(const AStatus: TOrderStatus): string;
begin
  Result := CNames[AStatus];
end;

end.
