{
  dump_masters.pas - dump master list of every plugin matching --target=
  pattern (or all loaded plugins if --target=*).
}
unit UserScript;

function Esc(const s: string): string;
begin
  Result := StringReplace(s, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
end;

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

function Initialize: Integer;
var
  pattern, outPath: string;
  out_: TStringList;
  i, j: Integer;
  f, mastersGroup, master: IInterface;
  fname: string;
  first: Boolean;
  firstMaster: Boolean;
begin
  pattern := GetArg('target');
  outPath := GetArg('out');
  if outPath = '' then begin
    AddMessage('Usage: dump_masters --target=pattern --out=path');
    Result := 1; Exit;
  end;

  out_ := TStringList.Create;
  out_.Add('{');
  out_.Add('  "results": [');
  first := True;
  for i := 0 to Pred(FileCount) do begin
    f := FileByIndex(i);
    fname := GetFileName(f);
    if (pattern <> '') and (pattern <> '*') and (Pos(pattern, fname) = 0) then Continue;
    if not first then out_.Add('    ,');
    first := False;
    out_.Add('    {');
    out_.Add('      "plugin": "' + Esc(fname) + '",');
    out_.Add('      "load_index": ' + IntToStr(i) + ',');
    out_.Add('      "masters": [');
    mastersGroup := ElementByPath(ElementByIndex(f, 0), 'Master Files');
    firstMaster := True;
    if Assigned(mastersGroup) then begin
      for j := 0 to Pred(ElementCount(mastersGroup)) do begin
        master := ElementByIndex(mastersGroup, j);
        if not firstMaster then out_.Add('        ,');
        firstMaster := False;
        out_.Add('        "' + Esc(GetEditValue(ElementByPath(master, 'MAST'))) + '"');
      end;
    end;
    out_.Add('      ]');
    out_.Add('    }');
  end;
  out_.Add('  ]');
  out_.Add('}');
  out_.SaveToFile(outPath);
  AddMessage('Wrote: ' + outPath);
  out_.Free;
  Result := 0;
end;

end.
