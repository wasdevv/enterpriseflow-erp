unit EF.Infrastructure.Http.Net;

{ Transporte Delphi com TNetHTTPClient. Mesma interface do transporte FCL.
  ESTADO: escrito contra a documentação, ainda não compilado (ver docs/verificacao-delphi.md). }

interface

uses
  System.SysUtils, System.Classes, System.Net.URLClient, System.Net.HttpClient,
  System.Net.HttpClientComponent,
  EF.Infrastructure.Http;

type
  TNetHttpTransport = class(TInterfacedObject, IHttpTransport)
  public
    function Send(const ARequest: THttpRequest): THttpResponse;
  end;

implementation

function TNetHttpTransport.Send(const ARequest: THttpRequest): THttpResponse;
var
  LClient: TNetHTTPClient;
  LHeaders: TNetHeaders;
  LBody: TStringStream;
  LResponse: IHTTPResponse;
  LIndex: Integer;
begin
  LClient := TNetHTTPClient.Create(nil);
  LBody := TStringStream.Create(ARequest.Body, TEncoding.UTF8);
  try
    LClient.ConnectionTimeout := ARequest.TimeoutMs;
    LClient.ResponseTimeout := ARequest.TimeoutMs;
    LClient.HandleRedirects := False;
    SetLength(LHeaders, Length(ARequest.Headers));
    for LIndex := 0 to High(ARequest.Headers) do
      LHeaders[LIndex] := TNameValuePair.Create(ARequest.Headers[LIndex].Name, ARequest.Headers[LIndex].Value);
    try
      if SameText(ARequest.Method, 'GET') then
        LResponse := LClient.Get(ARequest.Url, nil, LHeaders)
      else
        LResponse := LClient.Post(ARequest.Url, LBody, nil, LHeaders);
    except
      on E: ENetException do
        raise EHttpTransportError.Create(E.Message);
    end;
    Result.StatusCode := LResponse.StatusCode;
    Result.Body := LResponse.ContentAsString(TEncoding.UTF8);
  finally
    LBody.Free;
    LClient.Free;
  end;
end;

end.
