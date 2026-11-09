unit EF.Shared.Documents;

{$I EF.inc}

interface

uses
  SysUtils;

function OnlyDigits(const AText: string): string;
function IsValidCpf(const AText: string): Boolean;
function IsValidCnpj(const AText: string): Boolean;
function IsValidDocument(const AText: string): Boolean;
function IsValidEmail(const AText: string): Boolean;

implementation

function OnlyDigits(const AText: string): string;
var
  LIndex: Integer;
begin
  Result := '';
  for LIndex := 1 to Length(AText) do
    if CharInSet(AText[LIndex], ['0'..'9']) then
      Result := Result + AText[LIndex];
end;

function AllSameDigit(const ADigits: string): Boolean;
var
  LIndex: Integer;
begin
  Result := True;
  for LIndex := 2 to Length(ADigits) do
    if ADigits[LIndex] <> ADigits[1] then
      Exit(False);
end;

function DigitAt(const ADigits: string; const AIndex: Integer): Integer;
begin
  Result := Ord(ADigits[AIndex]) - Ord('0');
end;

function IsValidCpf(const AText: string): Boolean;
var
  LDigits: string;
  LRound, LIndex, LSum, LCheck: Integer;
begin
  LDigits := OnlyDigits(AText);
  if (Length(LDigits) <> 11) or AllSameDigit(LDigits) then
    Exit(False);
  for LRound := 9 to 10 do
  begin
    LSum := 0;
    for LIndex := 1 to LRound do
      LSum := LSum + DigitAt(LDigits, LIndex) * (LRound + 2 - LIndex);
    LCheck := (LSum * 10) mod 11;
    if LCheck = 10 then
      LCheck := 0;
    if LCheck <> DigitAt(LDigits, LRound + 1) then
      Exit(False);
  end;
  Result := True;
end;

function IsValidCnpj(const AText: string): Boolean;
const
  CWeights: array [1 .. 13] of Integer = (6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2);
var
  LDigits: string;
  LRound, LIndex, LSum, LCheck: Integer;
begin
  LDigits := OnlyDigits(AText);
  if (Length(LDigits) <> 14) or AllSameDigit(LDigits) then
    Exit(False);
  for LRound := 12 to 13 do
  begin
    LSum := 0;
    for LIndex := 1 to LRound do
      LSum := LSum + DigitAt(LDigits, LIndex) * CWeights[LIndex + 13 - LRound];
    LCheck := LSum mod 11;
    if LCheck < 2 then
      LCheck := 0
    else
      LCheck := 11 - LCheck;
    if LCheck <> DigitAt(LDigits, LRound + 1) then
      Exit(False);
  end;
  Result := True;
end;

function IsValidDocument(const AText: string): Boolean;
begin
  Result := IsValidCpf(AText) or IsValidCnpj(AText);
end;

function IsValidEmail(const AText: string): Boolean;
var
  LAt: Integer;
begin
  LAt := Pos('@', AText);
  Result := (LAt > 1) and (Pos('.', Copy(AText, LAt + 2, MaxInt)) > 0) and (Pos(' ', AText) = 0);
end;

end.
