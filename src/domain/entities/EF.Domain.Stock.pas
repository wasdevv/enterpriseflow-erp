unit EF.Domain.Stock;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Quantity;

type
  TMovementType = (mtEntry, mtReserve, mtRelease, mtIssue, mtTransferOut, mtTransferIn, mtAdjustment);
  TReservationStatus = (rsActive, rsReleased, rsConsumed);

  { Saldo de um produto em um depósito. Disponível = físico - reservado. Toda alteração
    passa por aqui, e quem chama já bloqueou a linha na transação. }
  TStockBalance = record
    OnHand: TQuantity;
    Reserved: TQuantity;
    function Available: TQuantity;
    function Receive(const AQuantity: TQuantity): TStockBalance;
    function Reserve(const AQuantity: TQuantity): TStockBalance;
    function ReleaseReservation(const AQuantity: TQuantity): TStockBalance;
    function ConsumeReservation(const AQuantity: TQuantity): TStockBalance;
    function TransferOut(const AQuantity: TQuantity): TStockBalance;
    function AdjustTo(const ACounted: TQuantity): TStockBalance;
  end;

function MovementTypeCode(const AType: TMovementType): string;
function ReservationStatusCode(const AStatus: TReservationStatus): string;
function ReservationStatusFromCode(const ACode: string): TReservationStatus;
procedure EnsureReservationActive(const AStatus: TReservationStatus);

implementation

uses
  EF.Domain.Exceptions;

const
  CMovementCodes: array [TMovementType] of string = ('ENTRY', 'RESERVE', 'RELEASE', 'ISSUE', 'TRANSFER_OUT', 'TRANSFER_IN', 'ADJUSTMENT');
  CReservationCodes: array [TReservationStatus] of string = ('ACTIVE', 'RELEASED', 'CONSUMED');

procedure EnsurePositive(const AQuantity: TQuantity);
begin
  if not AQuantity.IsPositive then
    raise EValidationError.Create('A quantidade deve ser maior que zero.');
end;

function TStockBalance.Available: TQuantity;
begin
  Result := OnHand - Reserved;
end;

function TStockBalance.Receive(const AQuantity: TQuantity): TStockBalance;
begin
  EnsurePositive(AQuantity);
  Result := Self;
  Result.OnHand := OnHand + AQuantity;
end;

function TStockBalance.Reserve(const AQuantity: TQuantity): TStockBalance;
begin
  EnsurePositive(AQuantity);
  if AQuantity > Available then
    raise EInsufficientStock.CreateFmt('Disponível: %s. Solicitado: %s.', [Available.ToText, AQuantity.ToText]);
  Result := Self;
  Result.Reserved := Reserved + AQuantity;
end;

function TStockBalance.ReleaseReservation(const AQuantity: TQuantity): TStockBalance;
begin
  EnsurePositive(AQuantity);
  if AQuantity > Reserved then
    raise EReservationClosed.CreateFmt('Reservado: %s. Liberação solicitada: %s.', [Reserved.ToText, AQuantity.ToText]);
  Result := Self;
  Result.Reserved := Reserved - AQuantity;
end;

function TStockBalance.ConsumeReservation(const AQuantity: TQuantity): TStockBalance;
begin
  EnsurePositive(AQuantity);
  if AQuantity > Reserved then
    raise EReservationClosed.CreateFmt('Reservado: %s. Baixa solicitada: %s.', [Reserved.ToText, AQuantity.ToText]);
  Result.OnHand := OnHand - AQuantity;
  Result.Reserved := Reserved - AQuantity;
end;

function TStockBalance.TransferOut(const AQuantity: TQuantity): TStockBalance;
begin
  EnsurePositive(AQuantity);
  if AQuantity > Available then
    raise EInsufficientStock.CreateFmt('Disponível: %s. Transferência solicitada: %s.', [Available.ToText, AQuantity.ToText]);
  Result := Self;
  Result.OnHand := OnHand - AQuantity;
end;

function TStockBalance.AdjustTo(const ACounted: TQuantity): TStockBalance;
begin
  if ACounted.IsNegative then
    raise EValidationError.Create('A contagem não pode ser negativa.');
  if ACounted < Reserved then
    raise EInsufficientStock.CreateFmt('Contagem %s é menor que o reservado %s. Cancele pedidos antes de ajustar.', [ACounted.ToText, Reserved.ToText]);
  Result := Self;
  Result.OnHand := ACounted;
end;

function MovementTypeCode(const AType: TMovementType): string;
begin
  Result := CMovementCodes[AType];
end;

function ReservationStatusCode(const AStatus: TReservationStatus): string;
begin
  Result := CReservationCodes[AStatus];
end;

function ReservationStatusFromCode(const ACode: string): TReservationStatus;
var
  LStatus: TReservationStatus;
begin
  for LStatus := Low(TReservationStatus) to High(TReservationStatus) do
    if CReservationCodes[LStatus] = ACode then
      Exit(LStatus);
  raise EValidationError.CreateFmt('Status de reserva desconhecido: "%s".', [ACode]);
end;

procedure EnsureReservationActive(const AStatus: TReservationStatus);
begin
  if AStatus <> rsActive then
    raise EReservationClosed.Create('Reserva já encerrada: não pode ser liberada nem baixada de novo.');
end;

end.
