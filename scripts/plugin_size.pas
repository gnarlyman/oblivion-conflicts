{
  plugin_size.pas - report which file path xEdit loaded for a target
  plugin (and its size). Useful for verifying USVFS overlay resolution.
}
unit UserScript;

function GetArg(const key: string): string;
var i: Integer; prefix, s: string;
begin
  Result := '';
  prefix := '--' + key + '=';
  for i := 0 to ParamCount do begin
    s := ParamStr(i);
    if Copy(s, 1, Length(prefix)) = prefix then begin
      Result := Copy(s, Length(prefix) + 1, MaxInt); Exit;
    end;
  end;
end;

function FindFileByName(const name: string): IInterface;
var i: Integer; f: IInterface;
begin
  Result := nil;
  for i := 0 to Pred(FileCount) do begin
    f := FileByIndex(i);
    if SameText(GetFileName(f), name) then begin Result := f; Exit; end;
  end;
end;

function Initialize: Integer;
var
  target, outPath: string;
  f: IInterface;
  out_: TStringList;
begin
  target := GetArg('target');
  outPath := GetArg('out');
  f := FindFileByName(target);
  if not Assigned(f) then begin
    AddMessage('ERROR: not loaded: ' + target);
    Result := 1; Exit;
  end;
  out_ := TStringList.Create;
  out_.Add('plugin_name: ' + GetFileName(f));
  out_.Add('GetLoadOrder: ' + IntToStr(GetLoadOrder(f)));
  out_.Add('RecordCount: ' + IntToStr(RecordCount(f)));
  out_.SaveToFile(outPath);
  AddMessage('Wrote ' + outPath);
  out_.Free;
  Result := 0;
end;

end.
