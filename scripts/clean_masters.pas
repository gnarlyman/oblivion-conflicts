{
  clean_masters.pas - call xEdit's CleanMasters() on a target plugin
  to strip unused masters added by careless saves (e.g. CSE's
  SaveLoadedESPsAsMasters bug). Saves and exits.

  Args:
    --target=plugin.esp   plugin to clean
}
unit UserScript;

function GetArg(const key: string): string;
var
  i: Integer;
  prefix, s: string;
begin
  Result := '';
  prefix := '--' + key + '=';
  for i := 0 to ParamCount do begin
    s := ParamStr(i);
    if Copy(s, 1, Length(prefix)) = prefix then begin
      Result := Copy(s, Length(prefix) + 1, MaxInt);
      Exit;
    end;
  end;
end;

function FindFileByName(const name: string): IInterface;
var
  i: Integer;
  f: IInterface;
begin
  Result := nil;
  for i := 0 to Pred(FileCount) do begin
    f := FileByIndex(i);
    if GetFileName(f) = name then begin
      Result := f;
      Exit;
    end;
  end;
end;

function Initialize: Integer;
var
  target: string;
  f, hdr, mastersGroup: IInterface;
  before, after: Integer;
begin
  target := GetArg('target');
  if target = '' then begin
    AddMessage('Usage: clean_masters --target=plugin.esp');
    Result := 1; Exit;
  end;

  f := FindFileByName(target);
  if not Assigned(f) then begin
    AddMessage('ERROR: target plugin not loaded: ' + target);
    Result := 1; Exit;
  end;

  hdr := ElementByIndex(f, 0);
  mastersGroup := ElementByPath(hdr, 'Master Files');
  if Assigned(mastersGroup) then before := ElementCount(mastersGroup) else before := 0;
  AddMessage('Before CleanMasters: ' + IntToStr(before) + ' masters in ' + target);

  CleanMasters(f);

  hdr := ElementByIndex(f, 0);
  mastersGroup := ElementByPath(hdr, 'Master Files');
  if Assigned(mastersGroup) then after := ElementCount(mastersGroup) else after := 0;
  AddMessage('After  CleanMasters: ' + IntToStr(after) + ' masters in ' + target);

  // Mark file as modified so xEdit will save it on exit
  SetIsEditable(f, True);
  SetIsModified(f, True);
  Result := 0;
end;

end.
