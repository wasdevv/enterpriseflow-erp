unit EF.Shared.Crypto;

{$I EF.inc}

interface

uses
  SysUtils;

type
  TBytes32 = array [0 .. 31] of Byte;

const
  CPasswordIterations = 120000;

function Sha256Hex(const AData: RawByteString): string;
function Pbkdf2Sha256Hex(const APassword, ASalt: RawByteString; const AIterations: Integer): string;
function HashPassword(const APassword, ASaltHex: string; const AIterations: Integer): string;
function NewSaltHex: string;
{ Comparação em tempo constante: não revela em qual byte a senha divergiu. }
function ConstantTimeEquals(const A, B: string): Boolean;

implementation

const
  K: array [0 .. 63] of Cardinal = (
    $428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5, $3956C25B, $59F111F1, $923F82A4, $AB1C5ED5,
    $D807AA98, $12835B01, $243185BE, $550C7DC3, $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174,
    $E49B69C1, $EFBE4786, $0FC19DC6, $240CA1CC, $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA,
    $983E5152, $A831C66D, $B00327C8, $BF597FC7, $C6E00BF3, $D5A79147, $06CA6351, $14292967,
    $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13, $650A7354, $766A0ABB, $81C2C92E, $92722C85,
    $A2BFE8A1, $A81A664B, $C24B8B70, $C76C51A3, $D192E819, $D6990624, $F40E3585, $106AA070,
    $19A4C116, $1E376C08, $2748774C, $34B0BCB5, $391C0CB3, $4ED8AA4A, $5B9CCA4F, $682E6FF3,
    $748F82EE, $78A5636F, $84C87814, $8CC70208, $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2);

type
  TShaState = array [0 .. 7] of Cardinal;

function RotR(const AValue: Cardinal; const ABits: Byte): Cardinal; inline;
begin
  Result := (AValue shr ABits) or (AValue shl (32 - ABits));
end;

procedure InitState(out AState: TShaState);
begin
  AState[0] := $6A09E667;
  AState[1] := $BB67AE85;
  AState[2] := $3C6EF372;
  AState[3] := $A54FF53A;
  AState[4] := $510E527F;
  AState[5] := $9B05688C;
  AState[6] := $1F83D9AB;
  AState[7] := $5BE0CD19;
end;

procedure ProcessBlock(var AState: TShaState; ABlock: PByte);
var
  W: array [0 .. 63] of Cardinal;
  T, S0, S1, T1, T2, A, B, C, D, E, F, G, H: Cardinal;
  I: Integer;
begin
  {$IFOPT Q+}{$DEFINE EF_RESTORE_Q}{$Q-}{$ENDIF}
  {$IFOPT R+}{$DEFINE EF_RESTORE_R}{$R-}{$ENDIF}
  for I := 0 to 15 do
  begin
    W[I] := (Cardinal(ABlock^) shl 24) or (Cardinal((ABlock + 1)^) shl 16) or (Cardinal((ABlock + 2)^) shl 8) or Cardinal((ABlock + 3)^);
    Inc(ABlock, 4);
  end;
  for I := 16 to 63 do
  begin
    T := W[I - 15];
    S0 := RotR(T, 7) xor RotR(T, 18) xor (T shr 3);
    T := W[I - 2];
    S1 := RotR(T, 17) xor RotR(T, 19) xor (T shr 10);
    W[I] := W[I - 16] + S0 + W[I - 7] + S1;
  end;
  A := AState[0]; B := AState[1]; C := AState[2]; D := AState[3];
  E := AState[4]; F := AState[5]; G := AState[6]; H := AState[7];
  for I := 0 to 63 do
  begin
    S1 := RotR(E, 6) xor RotR(E, 11) xor RotR(E, 25);
    T1 := H + S1 + ((E and F) xor ((not E) and G)) + K[I] + W[I];
    S0 := RotR(A, 2) xor RotR(A, 13) xor RotR(A, 22);
    T2 := S0 + ((A and B) xor (A and C) xor (B and C));
    H := G; G := F; F := E; E := D + T1;
    D := C; C := B; B := A; A := T1 + T2;
  end;
  Inc(AState[0], A); Inc(AState[1], B); Inc(AState[2], C); Inc(AState[3], D);
  Inc(AState[4], E); Inc(AState[5], F); Inc(AState[6], G); Inc(AState[7], H);
  {$IFDEF EF_RESTORE_Q}{$Q+}{$UNDEF EF_RESTORE_Q}{$ENDIF}
  {$IFDEF EF_RESTORE_R}{$R+}{$UNDEF EF_RESTORE_R}{$ENDIF}
end;

function Sha256(const AData: RawByteString): TBytes32;
var
  LState: TShaState;
  LBlock: array [0 .. 63] of Byte;
  LLength, LOffset, LRemaining, I: Integer;
  LBits: Int64;
begin
  InitState(LState);
  LLength := Length(AData);
  LOffset := 0;
  while LLength - LOffset >= 64 do
  begin
    ProcessBlock(LState, PByte(PAnsiChar(AData) + LOffset));
    Inc(LOffset, 64);
  end;
  FillChar(LBlock, SizeOf(LBlock), 0);
  LRemaining := LLength - LOffset;
  if LRemaining > 0 then
    Move((PAnsiChar(AData) + LOffset)^, LBlock[0], LRemaining);
  LBlock[LRemaining] := $80;
  if LRemaining >= 56 then
  begin
    ProcessBlock(LState, @LBlock[0]);
    FillChar(LBlock, SizeOf(LBlock), 0);
  end;
  LBits := Int64(LLength) * 8;
  for I := 0 to 7 do
    LBlock[63 - I] := Byte(LBits shr (I * 8));
  ProcessBlock(LState, @LBlock[0]);
  for I := 0 to 7 do
  begin
    Result[I * 4] := Byte(LState[I] shr 24);
    Result[I * 4 + 1] := Byte(LState[I] shr 16);
    Result[I * 4 + 2] := Byte(LState[I] shr 8);
    Result[I * 4 + 3] := Byte(LState[I]);
  end;
end;

function DigestToRaw(const ADigest: TBytes32): RawByteString;
begin
  SetLength(Result, 32);
  Move(ADigest[0], Result[1], 32);
end;

function BytesToHex(const ADigest: TBytes32): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to 31 do
    Result := Result + LowerCase(IntToHex(ADigest[I], 2));
end;

function Sha256Hex(const AData: RawByteString): string;
begin
  Result := BytesToHex(Sha256(AData));
end;

function HmacSha256(const AKey, AMessage: RawByteString): TBytes32;
var
  LKey, LInner, LOuter: RawByteString;
  I: Integer;
begin
  LKey := AKey;
  if Length(LKey) > 64 then
    LKey := DigestToRaw(Sha256(LKey));
  SetLength(LInner, 64);
  SetLength(LOuter, 64);
  for I := 1 to 64 do
  begin
    if I <= Length(LKey) then
    begin
      LInner[I] := AnsiChar(Ord(LKey[I]) xor $36);
      LOuter[I] := AnsiChar(Ord(LKey[I]) xor $5C);
    end
    else
    begin
      LInner[I] := AnsiChar($36);
      LOuter[I] := AnsiChar($5C);
    end;
  end;
  Result := Sha256(LOuter + DigestToRaw(Sha256(LInner + AMessage)));
end;

function Pbkdf2Sha256Hex(const APassword, ASalt: RawByteString; const AIterations: Integer): string;
var
  LBlock, LU: TBytes32;
  LCounter: RawByteString;
  I, J: Integer;
begin
  { Bloco único: 32 bytes de saída, o tamanho de um digest. }
  SetLength(LCounter, 4);
  LCounter[1] := AnsiChar(0);
  LCounter[2] := AnsiChar(0);
  LCounter[3] := AnsiChar(0);
  LCounter[4] := AnsiChar(1);
  LU := HmacSha256(APassword, ASalt + LCounter);
  LBlock := LU;
  for I := 2 to AIterations do
  begin
    LU := HmacSha256(APassword, DigestToRaw(LU));
    for J := 0 to 31 do
      LBlock[J] := LBlock[J] xor LU[J];
  end;
  Result := BytesToHex(LBlock);
end;

function HashPassword(const APassword, ASaltHex: string; const AIterations: Integer): string;
begin
  Result := Pbkdf2Sha256Hex(UTF8Encode(APassword), UTF8Encode(ASaltHex), AIterations);
end;

function NewSaltHex: string;
var
  LGuid: TGUID;
  LFirst, LSecond: string;
begin
  CreateGUID(LGuid);
  LFirst := GUIDToString(LGuid);
  CreateGUID(LGuid);
  LSecond := GUIDToString(LGuid);
  Result := LowerCase(StringReplace(StringReplace(StringReplace(LFirst + LSecond, '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]), '-', '', [rfReplaceAll]));
end;

function ConstantTimeEquals(const A, B: string): Boolean;
var
  I, LDiff: Integer;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  LDiff := 0;
  for I := 1 to Length(A) do
    LDiff := LDiff or (Ord(A[I]) xor Ord(B[I]));
  Result := LDiff = 0;
end;

end.
