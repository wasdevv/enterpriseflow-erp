unit NetStub;

{ NÃO É O System.Net. Só para conferir sintaxe e tipos do transporte Delphi (ver FireDACStub). }

interface

uses
  SysUtils, Classes;

type
  TNameValuePair = record
    Name, Value: string;
    constructor Create(const AName, AValue: string);
  end;
  TNetHeaders = array of TNameValuePair;

  ENetException = class(Exception);

  IHTTPResponse = interface
    function GetStatusCode: Integer;
    function ContentAsString(const AEncoding: TEncoding = nil): string;
    property StatusCode: Integer read GetStatusCode;
  end;

  TNetHTTPClient = class(TComponent)
  public
    ConnectionTimeout, ResponseTimeout: Integer;
    HandleRedirects: Boolean;
    function Get(const AURL: string; const AResponseContent: TStream = nil; const AHeaders: TNetHeaders = nil): IHTTPResponse;
    function Post(const AURL: string; const ASource: TStream; const AResponseContent: TStream = nil; const AHeaders: TNetHeaders = nil): IHTTPResponse;
  end;

implementation

constructor TNameValuePair.Create(const AName, AValue: string);
begin
  Name := AName;
  Value := AValue;
end;

function TNetHTTPClient.Get(const AURL: string; const AResponseContent: TStream; const AHeaders: TNetHeaders): IHTTPResponse;
begin
  Result := nil;
end;

function TNetHTTPClient.Post(const AURL: string; const ASource: TStream; const AResponseContent: TStream; const AHeaders: TNetHeaders): IHTTPResponse;
begin
  Result := nil;
end;

end.
