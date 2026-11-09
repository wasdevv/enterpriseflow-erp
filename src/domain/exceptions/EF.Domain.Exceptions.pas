unit EF.Domain.Exceptions;

{$I EF.inc}

interface

uses
  SysUtils;

type
  { Erro previsto de negócio: a mensagem é segura para mostrar ao usuário. }
  EDomainError = class(Exception);

  EValidationError = class(EDomainError);
  ENotFound = class(EDomainError);
  EInvalidTransition = class(EDomainError);
  EInsufficientStock = class(EDomainError);
  EReservationClosed = class(EDomainError);
  EOverpayment = class(EDomainError);
  ECreditLimitExceeded = class(EDomainError);
  EAlreadyReversed = class(EDomainError);
  ESegregationOfDuties = class(EDomainError);
  EPermissionDenied = class(EDomainError);
  EAuthenticationFailed = class(EDomainError);

  { Outro usuário segura o registro, ou houve deadlock. Vale tentar de novo. }
  EConcurrencyConflict = class(EDomainError);

  { Violação de UNIQUE. Serviços usam para reconhecer a repetição de uma operação. }
  EDuplicateKey = class(EDomainError);

  { O banco recusou por CHECK, FK ou trigger. Com o domínio correto, não acontece. }
  EIntegrityViolation = class(EDomainError);

implementation

end.
