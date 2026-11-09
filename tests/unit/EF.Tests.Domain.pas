unit EF.Tests.Domain;

{$I EF.inc}
{$M+}

interface

uses
  DUnitX.TestFramework;

type
  TOrderStateTests = class(TObject)
  published
    procedure AllowsOnlyTheDocumentedPath;
    procedure CancelAllowedOnlyBeforePicking;
    procedure InvoicedNeverGoesBackToDraft;
    procedure CodesRoundTrip;
  end;

  TStockBalanceTests = class(TObject)
  published
    procedure AvailableIsOnHandMinusReserved;
    procedure ReserveRefusesAboveAvailable;
    procedure ReserveAcceptsExactlyTheLastUnit;
    procedure ReleaseRefusesMoreThanReserved;
    procedure ConsumeDecreasesBothSides;
    procedure TransferCannotTouchReservedStock;
    procedure AdjustCannotGoBelowReserved;
    procedure ZeroQuantityIsRefused;
    procedure ClosedReservationCannotBeReleasedAgain;
  end;

  TReceivableTests = class(TObject)
  published
    procedure PartialSettlementUpdatesOutstanding;
    procedure SettlementAboveOutstandingIsRefused;
    procedure DiscountCountsAgainstOutstanding;
    procedure ReversalRestoresOutstanding;
    procedure PlanSumsExactlyToTotal;
    procedure PlanRejectsInvalidInput;
    procedure OverdueIsDerivedAndPaidIsNeverOverdue;
    procedure TitleStatusDerivesFromSettledAmount;
    procedure LateFeesAreZeroWhenPaidOnTime;
    procedure LateFeesFollowPolicy;
    procedure CreditPolicyAllowsExactlyTheLimit;
    procedure CreditPolicyRefusesAboveTheLimit;
  end;

  TDocumentTests = class(TObject)
  published
    procedure AcceptsValidCpfAndCnpj;
    procedure RejectsWrongCheckDigitsAndRepeatedDigits;
    procedure EmailBasicShape;
  end;

  TCryptoTests = class(TObject)
  published
    procedure Sha256MatchesNistVectors;
    procedure Pbkdf2MatchesPublishedVectors;
    procedure PasswordWithAccentsHashesItsUtf8Bytes;
    procedure SaltsAreUnique;
    procedure ConstantTimeEqualsComparesContentAndLength;
  end;

  TTextTests = class(TObject)
  published
    procedure SourceLiteralsAreUtf8;
    procedure BrazilianDateParsesAndRejects;
    procedure JsonEscapesControlCharsAndQuotes;
    procedure JsonBuilderProducesValidObject;
    procedure RedactionMasksSensitiveJsonFields;
    procedure RedactionMasksKeyValuePairs;
    procedure RedactionKeepsOtherFieldsIntact;
  end;

implementation

uses
  SysUtils,
  EF.Domain.Money, EF.Domain.Quantity, EF.Domain.Exceptions, EF.Domain.OrderState,
  EF.Domain.Stock, EF.Domain.Receivables, EF.Domain.Policies,
  EF.Shared.Documents, EF.Shared.Crypto, EF.Shared.Text;

function Q(const AText: string): TQuantity;
begin
  Result := TQuantity.Parse(AText);
end;

function M(const AText: string): TMoney;
begin
  Result := TMoney.Parse(AText);
end;

function Balance(const AOnHand, AReserved: string): TStockBalance;
begin
  Result.OnHand := Q(AOnHand);
  Result.Reserved := Q(AReserved);
end;

function Installment(const AAmount, APaid, ADiscount: string): TInstallmentState;
begin
  Result.Amount := M(AAmount);
  Result.PrincipalPaid := M(APaid);
  Result.DiscountGranted := M(ADiscount);
end;

{ TOrderStateTests }

procedure TOrderStateTests.AllowsOnlyTheDocumentedPath;
var
  LFrom, LTo: TOrderStatus;
  LExpected: Boolean;
begin
  for LFrom := Low(TOrderStatus) to High(TOrderStatus) do
    for LTo := Low(TOrderStatus) to High(TOrderStatus) do
    begin
      LExpected :=
        ((LFrom = osDraft) and (LTo = osConfirmed)) or
        ((LFrom = osConfirmed) and (LTo = osReserved)) or
        ((LFrom = osReserved) and (LTo = osPicking)) or
        ((LFrom = osPicking) and (LTo = osShipped)) or
        ((LFrom = osShipped) and (LTo = osInvoiced)) or
        ((LFrom in [osDraft, osConfirmed, osReserved]) and (LTo = osCancelled));
      Assert.AreEqual(BoolToStr(LExpected, True), BoolToStr(TOrderStateMachine.CanTransition(LFrom, LTo), True),
        TOrderStateMachine.ToCode(LFrom) + ' -> ' + TOrderStateMachine.ToCode(LTo));
    end;
end;

procedure TOrderStateTests.CancelAllowedOnlyBeforePicking;
begin
  Assert.IsTrue(TOrderStateMachine.CanCancel(osReserved));
  Assert.IsFalse(TOrderStateMachine.CanCancel(osPicking));
  Assert.IsFalse(TOrderStateMachine.CanCancel(osInvoiced));
  Assert.IsFalse(TOrderStateMachine.CanCancel(osCancelled));
end;

procedure TOrderStateTests.InvoicedNeverGoesBackToDraft;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    TOrderStateMachine.EnsureTransition(osInvoiced, osDraft);
  except
    on EInvalidTransition do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
end;

procedure TOrderStateTests.CodesRoundTrip;
var
  LStatus: TOrderStatus;
begin
  for LStatus := Low(TOrderStatus) to High(TOrderStatus) do
    Assert.IsTrue(TOrderStateMachine.FromCode(TOrderStateMachine.ToCode(LStatus)) = LStatus);
end;

{ TStockBalanceTests }

procedure TStockBalanceTests.AvailableIsOnHandMinusReserved;
begin
  Assert.AreEqual('7,5', Balance('10', '2,5').Available.ToText);
end;

procedure TStockBalanceTests.ReserveRefusesAboveAvailable;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    Balance('10', '8').Reserve(Q('2,001'));
  except
    on EInsufficientStock do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
end;

procedure TStockBalanceTests.ReserveAcceptsExactlyTheLastUnit;
var
  LAfter: TStockBalance;
begin
  LAfter := Balance('10', '9').Reserve(Q('1'));
  Assert.AreEqual('10', LAfter.Reserved.ToText);
  Assert.IsTrue(LAfter.Available.IsZero);
end;

procedure TStockBalanceTests.ReleaseRefusesMoreThanReserved;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    Balance('10', '1').ReleaseReservation(Q('2'));
  except
    on EReservationClosed do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
end;

procedure TStockBalanceTests.ConsumeDecreasesBothSides;
var
  LAfter: TStockBalance;
begin
  LAfter := Balance('10', '4').ConsumeReservation(Q('3'));
  Assert.AreEqual('7', LAfter.OnHand.ToText);
  Assert.AreEqual('1', LAfter.Reserved.ToText);
end;

procedure TStockBalanceTests.TransferCannotTouchReservedStock;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    Balance('10', '8').TransferOut(Q('3'));
  except
    on EInsufficientStock do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
  Assert.AreEqual('8', Balance('10', '8').TransferOut(Q('2')).OnHand.ToText);
end;

procedure TStockBalanceTests.AdjustCannotGoBelowReserved;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    Balance('10', '5').AdjustTo(Q('4'));
  except
    on EInsufficientStock do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
  Assert.AreEqual('5', Balance('10', '5').AdjustTo(Q('5')).OnHand.ToText);
end;

procedure TStockBalanceTests.ZeroQuantityIsRefused;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    Balance('10', '0').Reserve(TQuantity.Zero);
  except
    on EValidationError do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
end;

procedure TStockBalanceTests.ClosedReservationCannotBeReleasedAgain;
var
  LRaised: Boolean;
begin
  EnsureReservationActive(rsActive);
  LRaised := False;
  try
    EnsureReservationActive(rsReleased);
  except
    on EReservationClosed do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
end;

{ TReceivableTests }

procedure TReceivableTests.PartialSettlementUpdatesOutstanding;
var
  LAfter: TInstallmentState;
begin
  LAfter := Installment('100,00', '0', '0').ApplySettlement(M('30,00'), TMoney.Zero);
  Assert.AreEqual('70.00', LAfter.Outstanding.ToInvariant);
  Assert.AreEqual('30.00', LAfter.PrincipalPaid.ToInvariant);
end;

procedure TReceivableTests.SettlementAboveOutstandingIsRefused;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    Installment('100,00', '90,00', '0').ApplySettlement(M('10,01'), TMoney.Zero);
  except
    on EOverpayment do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
end;

procedure TReceivableTests.DiscountCountsAgainstOutstanding;
var
  LRaised: Boolean;
begin
  Assert.IsTrue(Installment('100,00', '0', '0').ApplySettlement(M('95,00'), M('5,00')).Outstanding.IsZero);
  LRaised := False;
  try
    Installment('100,00', '0', '0').ApplySettlement(M('95,00'), M('5,01'));
  except
    on EOverpayment do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
end;

procedure TReceivableTests.ReversalRestoresOutstanding;
var
  LAfter: TInstallmentState;
begin
  LAfter := Installment('100,00', '40,00', '5,00').RevertSettlement(M('40,00'), M('5,00'));
  Assert.AreEqual('100.00', LAfter.Outstanding.ToInvariant);
end;

procedure TReceivableTests.PlanSumsExactlyToTotal;
var
  LPlan: TInstallmentPlan;
  LSum: TMoney;
  LIndex: Integer;
begin
  LPlan := BuildInstallmentPlan(M('100,00'), 3, EncodeDate(2026, 1, 31), 30);
  Assert.AreEqual(3, Length(LPlan));
  LSum := TMoney.Zero;
  for LIndex := 0 to High(LPlan) do
    LSum := LSum + LPlan[LIndex].Amount;
  Assert.AreEqual('100.00', LSum.ToInvariant);
  Assert.AreEqual('33.34', LPlan[0].Amount.ToInvariant);
  Assert.AreEqual('33.33', LPlan[2].Amount.ToInvariant);
  Assert.AreEqual(2, LPlan[1].Number);
  Assert.IsTrue(LPlan[1].DueDate = EncodeDate(2026, 3, 2));
end;

procedure TReceivableTests.PlanRejectsInvalidInput;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    BuildInstallmentPlan(TMoney.FromCents(2), 3, Date, 30);
  except
    on EValidationError do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised, 'Parcela de zero centavo');
  LRaised := False;
  try
    BuildInstallmentPlan(M('10,00'), 0, Date, 30);
  except
    on EValidationError do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised, 'Zero parcelas');
end;

procedure TReceivableTests.OverdueIsDerivedAndPaidIsNeverOverdue;
var
  LDue: TDateTime;
begin
  LDue := EncodeDate(2026, 5, 10);
  Assert.IsFalse(Installment('10,00', '0', '0').IsOverdue(LDue, LDue), 'No dia do vencimento não atrasou');
  Assert.IsTrue(Installment('10,00', '0', '0').IsOverdue(LDue, LDue + 1));
  Assert.IsFalse(Installment('10,00', '10,00', '0').IsOverdue(LDue, LDue + 30), 'Quitada não atrasa');
end;

procedure TReceivableTests.TitleStatusDerivesFromSettledAmount;
begin
  Assert.AreEqual('OPEN', TitleStatusCode(DeriveTitleStatus(M('10,00'), TMoney.Zero)));
  Assert.AreEqual('PARTIALLY_PAID', TitleStatusCode(DeriveTitleStatus(M('10,00'), M('0,01'))));
  Assert.AreEqual('PAID', TitleStatusCode(DeriveTitleStatus(M('10,00'), M('10,00'))));
end;

procedure TReceivableTests.LateFeesAreZeroWhenPaidOnTime;
var
  LPolicy: TLateFeePolicy;
  LCharges: TLateCharges;
begin
  LPolicy.PenaltyBps := 200;
  LPolicy.MonthlyInterestBps := 100;
  LCharges := LPolicy.Compute(M('100,00'), EncodeDate(2026, 5, 10), EncodeDate(2026, 5, 10));
  Assert.IsTrue(LCharges.Penalty.IsZero);
  Assert.IsTrue(LCharges.Interest.IsZero);
end;

procedure TReceivableTests.LateFeesFollowPolicy;
var
  LPolicy: TLateFeePolicy;
  LCharges: TLateCharges;
begin
  LPolicy.PenaltyBps := 200;
  LPolicy.MonthlyInterestBps := 100;
  { 15 dias de atraso sobre R$ 1.000,00: multa 2% = 20,00; juros 1%/mês x 15/30 = 5,00 }
  LCharges := LPolicy.Compute(M('1000,00'), EncodeDate(2026, 5, 10), EncodeDate(2026, 5, 25));
  Assert.AreEqual('20.00', LCharges.Penalty.ToInvariant);
  Assert.AreEqual('5.00', LCharges.Interest.ToInvariant);
  { 1 dia sobre R$ 1.000,00: 1%/30 = 0,3333 -> 0,33. Dividir primeiro daria zero. }
  LCharges := LPolicy.Compute(M('1000,00'), EncodeDate(2026, 5, 10), EncodeDate(2026, 5, 11));
  Assert.AreEqual('0.33', LCharges.Interest.ToInvariant);
  { Valor alto expõe arredondamento intermediário: 1%/30 de 1.000.000,00 = 333,33. }
  LCharges := LPolicy.Compute(M('1000000,00'), EncodeDate(2026, 5, 10), EncodeDate(2026, 5, 11));
  Assert.AreEqual('333.33', LCharges.Interest.ToInvariant);
end;

procedure TReceivableTests.CreditPolicyAllowsExactlyTheLimit;
begin
  TCreditPolicy.Ensure(M('100,00'), M('60,00'), M('40,00'));
  Assert.Pass;
end;

procedure TReceivableTests.CreditPolicyRefusesAboveTheLimit;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    TCreditPolicy.Ensure(M('100,00'), M('60,00'), M('40,01'));
  except
    on ECreditLimitExceeded do
      LRaised := True;
  end;
  Assert.IsTrue(LRaised);
end;

{ TDocumentTests }

procedure TDocumentTests.AcceptsValidCpfAndCnpj;
begin
  Assert.IsTrue(IsValidCpf('529.982.247-25'));
  Assert.IsTrue(IsValidCnpj('11.222.333/0001-81'));
  Assert.IsTrue(IsValidDocument('52998224725'));
end;

procedure TDocumentTests.RejectsWrongCheckDigitsAndRepeatedDigits;
begin
  Assert.IsFalse(IsValidCpf('529.982.247-24'));
  Assert.IsFalse(IsValidCpf('111.111.111-11'));
  Assert.IsFalse(IsValidCnpj('11.222.333/0001-80'));
  Assert.IsFalse(IsValidCnpj('00.000.000/0000-00'));
  Assert.IsFalse(IsValidDocument('123'));
end;

procedure TDocumentTests.EmailBasicShape;
begin
  Assert.IsTrue(IsValidEmail('vendas@saolucas.example'));
  Assert.IsFalse(IsValidEmail('vendas'));
  Assert.IsFalse(IsValidEmail('@saolucas.example'));
  Assert.IsFalse(IsValidEmail('a b@c.d'));
end;

{ TCryptoTests }

procedure TCryptoTests.Sha256MatchesNistVectors;
var
  LLong: RawByteString;
begin
  Assert.AreEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', Sha256Hex(''));
  Assert.AreEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', Sha256Hex('abc'));
  { Mensagem que força o padding a ocupar um segundo bloco. }
  Assert.AreEqual('248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    Sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'));
  LLong := StringOfChar(AnsiChar('a'), 1000000);
  Assert.AreEqual('cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0', Sha256Hex(LLong));
end;

procedure TCryptoTests.Pbkdf2MatchesPublishedVectors;
begin
  Assert.AreEqual('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b', Pbkdf2Sha256Hex('password', 'salt', 1));
  Assert.AreEqual('ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43', Pbkdf2Sha256Hex('password', 'salt', 2));
  Assert.AreEqual('c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a', Pbkdf2Sha256Hex('password', 'salt', 4096));
end;

procedure TCryptoTests.PasswordWithAccentsHashesItsUtf8Bytes;
begin
  { Valor conferido com hashlib.pbkdf2_hmac('sha256', 'pão'.encode(), b'sal', 1000). }
  Assert.AreEqual('a35f096a1541a9f88afabad7dd73065b2775f343fc09cef8e189b166223e803b', HashPassword('pão', 'sal', 1000));
end;

procedure TCryptoTests.SaltsAreUnique;
var
  LFirst, LSecond: string;
begin
  LFirst := NewSaltHex;
  LSecond := NewSaltHex;
  Assert.AreEqual(64, Length(LFirst));
  Assert.IsTrue(LFirst <> LSecond);
end;

procedure TCryptoTests.ConstantTimeEqualsComparesContentAndLength;
begin
  Assert.IsTrue(ConstantTimeEquals('abc', 'abc'));
  Assert.IsFalse(ConstantTimeEquals('abc', 'abd'));
  Assert.IsFalse(ConstantTimeEquals('abc', 'abcd'));
end;

{ TTextTests }

procedure TTextTests.BrazilianDateParsesAndRejects;
const
  CBad: array [0 .. 4] of string = ('31/02/2026', '2026-01-01', '1/1/2026', '', 'aa/bb/cccc');
var
  LIndex: Integer;
  LRaised: Boolean;
begin
  Assert.IsTrue(ParseBrazilianDate('05/03/2026') = EncodeDate(2026, 3, 5), 'Dia antes do mês');
  for LIndex := Low(CBad) to High(CBad) do
  begin
    LRaised := False;
    try
      ParseBrazilianDate(CBad[LIndex]);
    except
      on EValidationError do
        LRaised := True;
    end;
    Assert.IsTrue(LRaised, 'Deveria recusar: ' + CBad[LIndex]);
  end;
end;

procedure TTextTests.SourceLiteralsAreUtf8;
begin
  { "ç" ocupa dois bytes: "Orçamento" tem 9 letras e 10 bytes em UTF-8. Falha se um fonte sem
    BOM for lido como ANSI pelo Delphi, ou se o locale corromper o literal. }
  Assert.AreEqual(10, Length(RawByteString(UTF8Encode(TOrderStateMachine.DisplayName(osDraft)))));
  Assert.AreEqual('Orçamento', TOrderStateMachine.DisplayName(osDraft));
end;

procedure TTextTests.JsonEscapesControlCharsAndQuotes;
begin
  Assert.AreEqual('a\"b\\c\nd\u0001', JsonEscape('a"b\c'#10'd'#1));
end;

procedure TTextTests.JsonBuilderProducesValidObject;
begin
  Assert.AreEqual('{"a":"x","b":2,"c":[1]}', TJsonObjectBuilder.New.Str('a', 'x').Int('b', 2).Raw('c', '[1]').ToJson);
end;

procedure TTextTests.RedactionMasksSensitiveJsonFields;
begin
  Assert.AreEqual('{"password":"***","ok":1}', RedactSecrets('{"password":"s3nh4","ok":1}'));
  Assert.AreEqual('{"card_number":"***"}', RedactSecrets('{"card_number":"4111111111111111"}'));
  Assert.AreEqual('{"token":"***"}', RedactSecrets('{"token":"a\"b"}'));
end;

procedure TTextTests.RedactionMasksKeyValuePairs;
begin
  Assert.AreEqual('Authorization: ***', RedactSecrets('Authorization: Bearer'));
  Assert.AreEqual('host=x;password=***;user=y', RedactSecrets('host=x;password=abc;user=y'));
end;

procedure TTextTests.RedactionKeepsOtherFieldsIntact;
begin
  Assert.AreEqual('{"order_id":7,"status":"RESERVED"}', RedactSecrets('{"order_id":7,"status":"RESERVED"}'));
end;

initialization
  TDUnitX.RegisterTestFixture(TOrderStateTests);
  TDUnitX.RegisterTestFixture(TStockBalanceTests);
  TDUnitX.RegisterTestFixture(TReceivableTests);
  TDUnitX.RegisterTestFixture(TDocumentTests);
  TDUnitX.RegisterTestFixture(TCryptoTests);
  TDUnitX.RegisterTestFixture(TTextTests);

end.
