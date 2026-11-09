unit EF.Infrastructure.Http.Fcl;

{ Transporte Free Pascal, para rodar a integração em CI contra o serviço simulado. }

{$I EF.inc}

interface

uses
  SysUtils, Classes, fphttpclient,
  EF.Infrastructure.Http;

type
  TFclHttpTransport = class(TInterfacedObject, IHttpTransport)
  public
    function Send(const ARequest: THttpRequest): THttpResponse;
  end;

implementation

function TFclHttpTransport.Send(const ARequest: THttpRequest): THttpResponse;
var
  LClient: TFPHTTPClient;
  LBody: TStringStream;
  LResponse: TStringStream;
  LIndex: Integer;
begin
  LClient := TFPHTTPClient.Create(nil);
  LResponse := TStringStream.Create('');
  LBody := nil;
  try
    LClient.ConnectTimeout := ARequest.TimeoutMs;
    LClient.IOTimeout := ARequest.TimeoutMs;
    LClient.AllowRedirect := False;
    for LIndex := 0 to High(ARequest.Headers) do
      LClient.AddHeader(ARequest.Headers[LIndex].Name, ARequest.Headers[LIndex].Value);
    if ARequest.Body <> '' then
    begin
      LBody := TStringStream.Create(ARequest.Body);
      LClient.RequestBody := LBody;
    end;
    try
      LClient.HTTPMethod(ARequest.Method, ARequest.Url, LResponse, []);
    except
      on E: Exception do
        raise EHttpTransportError.Create(E.Message);
    end;
    Result.StatusCode := LClient.ResponseStatusCode;
    Result.Body := LResponse.DataString;
    { O cliente da FCL devolve status 0 quando o IOTimeout estoura sem exceção. }
    if Result.StatusCode = 0 then
      raise EHttpTransportError.Create('Sem resposta do servidor (timeout).');
  finally
    LClient.RequestBody := nil;
    LBody.Free;
    LResponse.Free;
    LClient.Free;
  end;
end;

end.
