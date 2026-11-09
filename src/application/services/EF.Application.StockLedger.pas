unit EF.Application.StockLedger;

{ Toda alteração de saldo passa por aqui: bloqueia a linha, aplica a regra de domínio,
  grava o saldo e o movimento na mesma transação, que quem chama já abriu. }

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Quantity, EF.Domain.Stock,
  EF.Application.Ports;

type
  TStockSource = record
    SourceType: string;
    SourceId: Int64;
    Reason: string;
    class function Make(const ASourceType: string; const ASourceId: Int64; const AReason: string): TStockSource; static;
  end;

  TStockLedger = record
  private
    FStock: IStockRepository;
    FUserId: Int64;
    FCorrelationId: string;
    procedure Post(const AProductId, AWarehouseId: Int64; const AType: TMovementType; const AQuantity: TQuantity;
      const ABefore, AAfter: TStockBalance; const ASource: TStockSource);
  public
    class function Make(const AStock: IStockRepository; const ACtx: TUserContext): TStockLedger; static;
    procedure Receive(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
    procedure Reserve(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
    procedure Release(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
    procedure Consume(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
    procedure TransferOut(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
    procedure TransferIn(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
    { Sem diferença em relação à contagem, nada é gravado e devolve False. }
    function AdjustTo(const AProductId, AWarehouseId: Int64; const ACounted: TQuantity; const ASource: TStockSource): Boolean;
    { Bloqueia e revalida sem alterar nada. Lança EInsufficientStock nomeando o produto. }
    procedure LockAndEnsureAvailable(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity);
  end;

implementation

uses
  EF.Domain.Exceptions;

class function TStockSource.Make(const ASourceType: string; const ASourceId: Int64; const AReason: string): TStockSource;
begin
  if Trim(AReason) = '' then
    raise EValidationError.Create('Movimentação de estoque exige motivo.');
  Result.SourceType := ASourceType;
  Result.SourceId := ASourceId;
  Result.Reason := AReason;
end;

class function TStockLedger.Make(const AStock: IStockRepository; const ACtx: TUserContext): TStockLedger;
begin
  Result.FStock := AStock;
  Result.FUserId := ACtx.UserId;
  Result.FCorrelationId := ACtx.CorrelationId;
end;

procedure TStockLedger.Post(const AProductId, AWarehouseId: Int64; const AType: TMovementType; const AQuantity: TQuantity;
  const ABefore, AAfter: TStockBalance; const ASource: TStockSource);
var
  LMovement: TMovementRecord;
begin
  FStock.SaveBalance(AProductId, AWarehouseId, AAfter);
  LMovement.ProductId := AProductId;
  LMovement.WarehouseId := AWarehouseId;
  LMovement.MovementType := AType;
  LMovement.Quantity := AQuantity;
  LMovement.OnHandDelta := AAfter.OnHand - ABefore.OnHand;
  LMovement.ReservedDelta := AAfter.Reserved - ABefore.Reserved;
  LMovement.OnHandAfter := AAfter.OnHand;
  LMovement.ReservedAfter := AAfter.Reserved;
  LMovement.Reason := ASource.Reason;
  LMovement.UserId := FUserId;
  LMovement.SourceType := ASource.SourceType;
  LMovement.SourceId := ASource.SourceId;
  LMovement.CorrelationId := FCorrelationId;
  FStock.AddMovement(LMovement);
end;

procedure TStockLedger.Receive(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
var
  LBefore: TStockBalance;
begin
  FStock.EnsureBalance(AProductId, AWarehouseId);
  FStock.LockBalance(AProductId, AWarehouseId, LBefore);
  Post(AProductId, AWarehouseId, mtEntry, AQuantity, LBefore, LBefore.Receive(AQuantity), ASource);
end;

procedure TStockLedger.LockAndEnsureAvailable(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity);
var
  LBalance: TStockBalance;
begin
  FStock.LockBalance(AProductId, AWarehouseId, LBalance);
  try
    LBalance.Reserve(AQuantity);
  except
    on E: EInsufficientStock do
      raise EInsufficientStock.CreateFmt('%s: %s', [FStock.DescribeKey(AProductId, AWarehouseId), E.Message]);
  end;
end;

procedure TStockLedger.Reserve(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
var
  LBefore: TStockBalance;
begin
  FStock.LockBalance(AProductId, AWarehouseId, LBefore);
  Post(AProductId, AWarehouseId, mtReserve, AQuantity, LBefore, LBefore.Reserve(AQuantity), ASource);
end;

procedure TStockLedger.Release(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
var
  LBefore: TStockBalance;
begin
  FStock.LockBalance(AProductId, AWarehouseId, LBefore);
  Post(AProductId, AWarehouseId, mtRelease, AQuantity, LBefore, LBefore.ReleaseReservation(AQuantity), ASource);
end;

procedure TStockLedger.Consume(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
var
  LBefore: TStockBalance;
begin
  FStock.LockBalance(AProductId, AWarehouseId, LBefore);
  Post(AProductId, AWarehouseId, mtIssue, AQuantity, LBefore, LBefore.ConsumeReservation(AQuantity), ASource);
end;

procedure TStockLedger.TransferOut(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
var
  LBefore: TStockBalance;
begin
  FStock.LockBalance(AProductId, AWarehouseId, LBefore);
  try
    Post(AProductId, AWarehouseId, mtTransferOut, AQuantity, LBefore, LBefore.TransferOut(AQuantity), ASource);
  except
    on E: EInsufficientStock do
      raise EInsufficientStock.CreateFmt('%s: %s', [FStock.DescribeKey(AProductId, AWarehouseId), E.Message]);
  end;
end;

procedure TStockLedger.TransferIn(const AProductId, AWarehouseId: Int64; const AQuantity: TQuantity; const ASource: TStockSource);
var
  LBefore: TStockBalance;
begin
  FStock.EnsureBalance(AProductId, AWarehouseId);
  FStock.LockBalance(AProductId, AWarehouseId, LBefore);
  Post(AProductId, AWarehouseId, mtTransferIn, AQuantity, LBefore, LBefore.Receive(AQuantity), ASource);
end;

function TStockLedger.AdjustTo(const AProductId, AWarehouseId: Int64; const ACounted: TQuantity; const ASource: TStockSource): Boolean;
var
  LBefore, LAfter: TStockBalance;
  LDifference: TQuantity;
begin
  FStock.EnsureBalance(AProductId, AWarehouseId);
  FStock.LockBalance(AProductId, AWarehouseId, LBefore);
  LAfter := LBefore.AdjustTo(ACounted);
  LDifference := LAfter.OnHand - LBefore.OnHand;
  Result := not LDifference.IsZero;
  if not Result then
    Exit;
  if LDifference.IsNegative then
    LDifference := LDifference.Negated;
  Post(AProductId, AWarehouseId, mtAdjustment, LDifference, LBefore, LAfter, ASource);
end;

end.
