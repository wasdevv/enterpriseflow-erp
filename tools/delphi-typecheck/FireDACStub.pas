unit FireDACStub;

{ NÃO É O FIREDAC. Declara só o que o adaptador usa, com as assinaturas conhecidas pela
  documentação, para o Free Pascal conferir sintaxe e tipos dos ramos exclusivos de Delphi.
  Passar aqui não prova que a API real é assim: só a compilação em Delphi prova. }

interface

uses
  SysUtils, Classes, DB;

type
  TFDTxIsolation = (xiUnspecified, xiDirtyRead, xiReadCommitted, xiRepeatableRead, xiSnapshot, xiSerializable);

  TFDTxOptions = class
  public
    AutoCommit, AutoStart, AutoStop, ReadOnly: Boolean;
    Isolation: TFDTxIsolation;
    Params: TStrings;
  end;

  TFDResourceOptions = class
  public
    SilentMode, MacroCreate, MacroExpand, EscapeExpand, ParamCreate: Boolean;
  end;

  TFDUpdateOptions = class
  public
    LockWait, ReadOnly, RequestLive: Boolean;
  end;

  TFDFetchOptions = class
  public
    Unidirectional: Boolean;
  end;

  TFDCustomTransaction = class;

  TFDConnection = class(TComponent)
  public
    LoginPrompt: Boolean;
    ResourceOptions: TFDResourceOptions;
    Params: TStrings;
    TxOptions: TFDTxOptions;
    UpdateOptions: TFDUpdateOptions;
    Transaction: TFDCustomTransaction;
    UpdateTransaction: TFDCustomTransaction;
    procedure Open;
    procedure Close;
  end;

  TFDCustomTransaction = class(TComponent)
  public
    Connection: TFDConnection;
    Options: TFDTxOptions;
    Active: Boolean;
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
  end;

  TFDTransaction = class(TFDCustomTransaction);

  TFDParam = class
  public
    DataType: TFieldType;
    AsLargeInt: Int64;
    AsString: string;
    AsCurrency: Currency;
    AsDateTime: TDateTime;
    AsDate: TDateTime;
    AsBoolean: Boolean;
    procedure Clear;
  end;

  TFDQuery = class(TDataSet)
  public
    Connection: TFDConnection;
    Transaction: TFDCustomTransaction;
    UpdateTransaction: TFDCustomTransaction;
    UpdateOptions: TFDUpdateOptions;
    ResourceOptions: TFDResourceOptions;
    FetchOptions: TFDFetchOptions;
    SQL: TStrings;
    RowsAffected: Integer;
    function ParamByName(const AName: string): TFDParam;
    procedure ExecSQL;
  end;

  TFDDBError = class
  public
    ErrorCode: Integer;
  end;

  EFDDBEngineException = class(Exception)
  private
    function GetError(AIndex: Integer): TFDDBError;
  public
    ErrorCount: Integer;
    property Errors[AIndex: Integer]: TFDDBError read GetError;
  end;

implementation

procedure TFDConnection.Open;
begin
end;

procedure TFDConnection.Close;
begin
end;

procedure TFDCustomTransaction.StartTransaction;
begin
end;

procedure TFDCustomTransaction.Commit;
begin
end;

procedure TFDCustomTransaction.Rollback;
begin
end;

procedure TFDParam.Clear;
begin
end;

function TFDQuery.ParamByName(const AName: string): TFDParam;
begin
  Result := nil;
end;

procedure TFDQuery.ExecSQL;
begin
end;

function EFDDBEngineException.GetError(AIndex: Integer): TFDDBError;
begin
  Result := nil;
end;

end.
