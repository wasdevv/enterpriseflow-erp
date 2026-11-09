unit IOUtilsStub;

interface

type
  TPath = class
  public
    class function GetTempPath: string; static;
  end;

implementation

class function TPath.GetTempPath: string;
begin
  Result := '';
end;

end.
