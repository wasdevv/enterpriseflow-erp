unit EF.Application.Inventory;

{$I EF.inc}

interface

uses
  SysUtils,
  EF.Domain.Money, EF.Domain.Quantity,
  EF.Application.Ports, EF.Application.Base;

type
  TStockService = class(TServiceBase)
  public
    { Debita e credita na mesma transação, bloqueando os depósitos em ordem crescente. }
    function Transfer(const AProductId, AFromWarehouseId, AToWarehouseId: Int64; const AQuantity: TQuantity; const AReason: string): Int64;
    function RequestAdjustment(const AProductId, AWarehouseId: Int64; const ACounted: TQuantity; const AReason: string): Int64;
    procedure ApproveAdjustment(const AAdjustmentId: Int64);
    procedure RejectAdjustment(const AAdjustmentId: Int64);
  end;

  TPurchaseLineInput = record
    ProductId: Int64;
    Quantity: TQuantity;
    UnitCost: TMoney;
  end;
  TPurchaseLineInputs = array of TPurchaseLineInput;

  TReceiptLineInput = record
    ItemId: Int64;
    Quantity: TQuantity;
    Note: string;
  end;
  TReceiptLineInputs = array of TReceiptLineInput;

  TPurchaseService = class(TServiceBase)
  public
    function CreateOrder(const ASupplierId, AWarehouseId: Int64; const ALines: TPurchaseLineInputs; const ANote: string): Int64;
    { Recebimento parcial ou total. Devolve False se a chave já tinha sido processada. }
    function Receive(const AOrderId: Int64; const ALines: TReceiptLineInputs; const AIdempotencyKey, ANote: string): Boolean;
    procedure CloseShort(const AOrderId: Int64; const AReason: string);
  end;

implementation

uses
  EF.Domain.Exceptions,
  EF.Application.StockLedger,
  EF.Shared.Text;

function TStockService.Transfer(const AProductId, AFromWarehouseId, AToWarehouseId: Int64; const AQuantity: TQuantity; const AReason: string): Int64;
var
  LLedger: TStockLedger;
  LSource: TStockSource;
begin
  BeginOperation(PermStockMove);
  if AFromWarehouseId = AToWarehouseId then
    raise EValidationError.Create('Origem e destino da transferência devem ser diferentes.');
  if not AQuantity.IsPositive then
    raise EValidationError.Create('A quantidade deve ser maior que zero.');
  if Trim(AReason) = '' then
    raise EValidationError.Create('Transferência exige motivo.');
  FUow.StartTransaction;
  try
    Result := FUow.Stock.AddTransfer(AProductId, AFromWarehouseId, AToWarehouseId, AQuantity, AReason, FCtx.UserId);
    LLedger := TStockLedger.Make(FUow.Stock, FCtx);
    LSource := TStockSource.Make('STOCK_TRANSFER', Result, AReason);
    { A ordem segue o id do depósito, não a direção: A->B e B->A simultâneos não travam. }
    if AFromWarehouseId < AToWarehouseId then
    begin
      LLedger.TransferOut(AProductId, AFromWarehouseId, AQuantity, LSource);
      LLedger.TransferIn(AProductId, AToWarehouseId, AQuantity, LSource);
    end
    else
    begin
      LLedger.TransferIn(AProductId, AToWarehouseId, AQuantity, LSource);
      LLedger.TransferOut(AProductId, AFromWarehouseId, AQuantity, LSource);
    end;
    Audit('stock.transferred', 'stock_transfer', Result, TJsonObjectBuilder.New.Int('product_id', AProductId)
      .Int('from', AFromWarehouseId).Int('to', AToWarehouseId).Str('quantity', AQuantity.ToText).ToJson);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

function TStockService.RequestAdjustment(const AProductId, AWarehouseId: Int64; const ACounted: TQuantity; const AReason: string): Int64;
begin
  BeginOperation(PermStockAdjustRequest);
  if Trim(AReason) = '' then
    raise EValidationError.Create('Ajuste de inventário exige justificativa.');
  if ACounted.IsNegative then
    raise EValidationError.Create('A contagem não pode ser negativa.');
  FUow.StartTransaction;
  try
    Result := FUow.Stock.AddAdjustment(AProductId, AWarehouseId, ACounted, AReason, FCtx.UserId);
    Audit('stock.adjustment_requested', 'stock_adjustment', Result, TJsonObjectBuilder.New.Str('counted', ACounted.ToText).Str('reason', AReason).ToJson);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

procedure TStockService.ApproveAdjustment(const AAdjustmentId: Int64);
var
  LAdjustment: TAdjustmentRecord;
  LLedger: TStockLedger;
begin
  BeginOperation(PermStockAdjustApprove);
  FUow.StartTransaction;
  try
    if not FUow.Stock.LockAdjustment(AAdjustmentId, LAdjustment) then
      raise ENotFound.CreateFmt('Ajuste %d não encontrado.', [AAdjustmentId]);
    if LAdjustment.Status <> 'PENDING' then
      raise EInvalidTransition.Create('Este ajuste já foi decidido.');
    if LAdjustment.RequestedBy = FCtx.UserId then
      raise ESegregationOfDuties.Create('Quem solicita o ajuste não pode aprová-lo.');
    LLedger := TStockLedger.Make(FUow.Stock, FCtx);
    LLedger.AdjustTo(LAdjustment.ProductId, LAdjustment.WarehouseId, LAdjustment.Counted,
      TStockSource.Make('STOCK_ADJUSTMENT', AAdjustmentId, LAdjustment.Reason));
    FUow.Stock.DecideAdjustment(AAdjustmentId, 'APPROVED', FCtx.UserId);
    Audit('stock.adjustment_approved', 'stock_adjustment', AAdjustmentId);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

procedure TStockService.RejectAdjustment(const AAdjustmentId: Int64);
var
  LAdjustment: TAdjustmentRecord;
begin
  BeginOperation(PermStockAdjustApprove);
  FUow.StartTransaction;
  try
    if not FUow.Stock.LockAdjustment(AAdjustmentId, LAdjustment) then
      raise ENotFound.CreateFmt('Ajuste %d não encontrado.', [AAdjustmentId]);
    if LAdjustment.Status <> 'PENDING' then
      raise EInvalidTransition.Create('Este ajuste já foi decidido.');
    if LAdjustment.RequestedBy = FCtx.UserId then
      raise ESegregationOfDuties.Create('Quem solicita o ajuste não pode decidi-lo.');
    FUow.Stock.DecideAdjustment(AAdjustmentId, 'REJECTED', FCtx.UserId);
    Audit('stock.adjustment_rejected', 'stock_adjustment', AAdjustmentId);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

function TPurchaseService.CreateOrder(const ASupplierId, AWarehouseId: Int64; const ALines: TPurchaseLineInputs; const ANote: string): Int64;
var
  LIndex: Integer;
begin
  BeginOperation(PermPurchaseManage);
  if Length(ALines) = 0 then
    raise EValidationError.Create('O pedido de compra precisa de ao menos um item.');
  FUow.StartTransaction;
  try
    Result := FUow.Purchases.Insert(ASupplierId, AWarehouseId, ANote, FCtx.UserId);
    for LIndex := 0 to High(ALines) do
    begin
      if not ALines[LIndex].Quantity.IsPositive then
        raise EValidationError.Create('A quantidade de cada item deve ser maior que zero.');
      if ALines[LIndex].UnitCost.IsNegative then
        raise EValidationError.Create('O custo não pode ser negativo.');
      FUow.Purchases.InsertItem(Result, ALines[LIndex].ProductId, ALines[LIndex].Quantity, ALines[LIndex].UnitCost);
    end;
    Audit('purchase.created', 'purchase_order', Result);
    FUow.Commit;
  except
    on E: EDuplicateKey do
    begin
      FUow.Rollback;
      raise EValidationError.Create('O mesmo produto aparece duas vezes no pedido de compra.');
    end;
    on E: Exception do
    begin
      FUow.Rollback;
      raise;
    end;
  end;
end;

function TPurchaseService.Receive(const AOrderId: Int64; const ALines: TReceiptLineInputs; const AIdempotencyKey, ANote: string): Boolean;
var
  LHeader: TPurchaseHeader;
  LItems: TPurchaseItemArray;
  LReceiptId: Int64;
  LLedger: TStockLedger;
  LLineIndex, LItemIndex, LMatch: Integer;
  LOutstanding, LNewReceived, LDivergence: TQuantity;
  LAllReceived: Boolean;
  LSource: TStockSource;
  LProcessed: array of Boolean;
begin
  BeginOperation(PermPurchaseManage);
  if Trim(AIdempotencyKey) = '' then
    raise EValidationError.Create('Recebimento exige chave de idempotência.');
  if Length(ALines) = 0 then
    raise EValidationError.Create('Informe ao menos um item recebido.');
  Result := True;
  FUow.StartTransaction;
  try
    if not FUow.Purchases.Lock(AOrderId, LHeader) then
      raise ENotFound.CreateFmt('Pedido de compra %d não encontrado.', [AOrderId]);
    if FUow.Purchases.FindReceiptByKey(AIdempotencyKey, LReceiptId) then
    begin
      Result := False;
      FUow.Commit;
      Exit;
    end;
    if (LHeader.Status = 'RECEIVED') or (LHeader.Status = 'CLOSED_SHORT') then
      raise EInvalidTransition.Create('Pedido de compra já encerrado.');

    LItems := FUow.Purchases.Items(AOrderId);
    LReceiptId := FUow.Purchases.InsertReceipt(AOrderId, AIdempotencyKey, ANote, FCtx.UserId);
    LLedger := TStockLedger.Make(FUow.Stock, FCtx);
    LSource := TStockSource.Make('PURCHASE_RECEIPT', LReceiptId, 'Recebimento do pedido de compra ' + IntToStr(AOrderId));

    { Percorre na ordem de produto de LItems: mesma ordem de bloqueio de todo o sistema. }
    SetLength(LProcessed, Length(ALines));
    for LLineIndex := 0 to High(LProcessed) do
      LProcessed[LLineIndex] := False;
    for LItemIndex := 0 to High(LItems) do
    begin
      LMatch := -1;
      for LLineIndex := 0 to High(ALines) do
        if ALines[LLineIndex].ItemId = LItems[LItemIndex].Id then
        begin
          if LMatch >= 0 then
            raise EValidationError.Create('O mesmo item aparece duas vezes no recebimento.');
          LMatch := LLineIndex;
        end;
      if LMatch < 0 then
        Continue;
      LProcessed[LMatch] := True;
      if not ALines[LMatch].Quantity.IsPositive then
        raise EValidationError.Create('A quantidade recebida deve ser maior que zero.');
      LOutstanding := LItems[LItemIndex].Ordered - LItems[LItemIndex].Received;
      LDivergence := ALines[LMatch].Quantity - LOutstanding;
      if LDivergence.IsPositive and (Trim(ALines[LMatch].Note) = '') then
        raise EValidationError.Create('Recebimento acima do pedido exige observação da divergência.');
      LNewReceived := LItems[LItemIndex].Received + ALines[LMatch].Quantity;
      FUow.Purchases.InsertReceiptItem(LReceiptId, LItems[LItemIndex].Id, ALines[LMatch].Quantity, LOutstanding, LDivergence, ALines[LMatch].Note);
      FUow.Purchases.UpdateItemReceived(LItems[LItemIndex].Id, LNewReceived);
      LItems[LItemIndex].Received := LNewReceived;
      LLedger.Receive(LItems[LItemIndex].ProductId, LHeader.WarehouseId, ALines[LMatch].Quantity, LSource);
    end;
    for LLineIndex := 0 to High(LProcessed) do
      if not LProcessed[LLineIndex] then
        raise EValidationError.Create('Item recebido não pertence a este pedido de compra.');

    LAllReceived := True;
    for LItemIndex := 0 to High(LItems) do
      if LItems[LItemIndex].Received < LItems[LItemIndex].Ordered then
        LAllReceived := False;
    if LAllReceived then
      FUow.Purchases.UpdateStatus(AOrderId, 'RECEIVED')
    else
      FUow.Purchases.UpdateStatus(AOrderId, 'PARTIALLY_RECEIVED');
    Audit('purchase.received', 'purchase_order', AOrderId, TJsonObjectBuilder.New.Int('receipt_id', LReceiptId).ToJson);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

procedure TPurchaseService.CloseShort(const AOrderId: Int64; const AReason: string);
var
  LHeader: TPurchaseHeader;
begin
  BeginOperation(PermPurchaseManage);
  if Trim(AReason) = '' then
    raise EValidationError.Create('Encerrar com falta exige motivo.');
  FUow.StartTransaction;
  try
    if not FUow.Purchases.Lock(AOrderId, LHeader) then
      raise ENotFound.CreateFmt('Pedido de compra %d não encontrado.', [AOrderId]);
    if (LHeader.Status = 'RECEIVED') or (LHeader.Status = 'CLOSED_SHORT') then
      raise EInvalidTransition.Create('Pedido de compra já encerrado.');
    FUow.Purchases.UpdateStatus(AOrderId, 'CLOSED_SHORT');
    Audit('purchase.closed_short', 'purchase_order', AOrderId, TJsonObjectBuilder.New.Str('reason', AReason).ToJson);
    FUow.Commit;
  except
    FUow.Rollback;
    raise;
  end;
end;

end.
