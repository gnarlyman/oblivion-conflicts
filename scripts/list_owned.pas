{
  list_owned.pas - emit every main record owned by --target plugin
  (chain[0] == target), regardless of conflict status.

  Args:
    --target=<plugin filename>     required
    --out=<path>                   required
    --sigs=<comma-list>            optional, e.g. "QUST,SCPT,GLOB"
}
unit UserScript;

var
  filterSigs: TStringList;
  hasFilter: boolean;

function Esc(const s: string): string;
begin
  Result := StringReplace(s, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
  Result := '"' + Result + '"';
end;

function GetArg(const key: string): string;
var
  i: integer;
  prefix, s: string;
begin
  Result := '';
  prefix := '--' + key + '=';
  for i := 0 to ParamCount do begin
    s := ParamStr(i);
    if Copy(s, 1, Length(prefix)) = prefix then begin
      Result := Copy(s, Length(prefix) + 1, Length(s));
      Exit;
    end;
  end;
end;

procedure WriteOutput(const path, content: string);
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := content;
    sl.SaveToFile(path);
  finally
    sl.Free;
  end;
end;

function ParseFilterSigs(const s: string): TStringList;
var
  i, start: integer;
  part: string;
begin
  Result := TStringList.Create;
  if s = '' then Exit;
  start := 1;
  for i := 1 to Length(s) do begin
    if s[i] = ',' then begin
      part := Trim(Copy(s, start, i - start));
      if part <> '' then Result.Add(part);
      start := i + 1;
    end;
  end;
  part := Trim(Copy(s, start, Length(s) - start + 1));
  if part <> '' then Result.Add(part);
end;

function FindFile(const fname: string): IInterface;
var i: integer; f: IInterface;
begin
  Result := nil;
  for i := 0 to FileCount - 1 do begin
    f := FileByLoadOrder(i);
    if GetFileName(f) = fname then begin
      Result := f;
      Exit;
    end;
  end;
end;

function Initialize: integer;
var
  outPath, target, sigsArg, results, buf, sig, edid: string;
  fids: TStringList;
  pluginFile, group, rec: IInterface;
  groupCount, i, j, recCount: integer;
  emittedOne: boolean;
begin
  Result := 0;
  outPath := GetArg('out');
  target := GetArg('target');
  sigsArg := GetArg('sigs');

  filterSigs := ParseFilterSigs(sigsArg);
  hasFilter := filterSigs.Count > 0;

  if (outPath = '') or (target = '') then begin
    WriteOutput('D:/Modlists/_clones/oblivion-conflicts/tests/.tmp/list_owned_error.json',
                '{"error":"need --out and --target"}');
    filterSigs.Free;
    Exit;
  end;

  pluginFile := FindFile(target);
  if not Assigned(pluginFile) then begin
    WriteOutput(outPath, '{"error":"plugin_not_loaded","target":' + Esc(target) + '}');
    filterSigs.Free;
    Exit;
  end;

  results := '';
  emittedOne := False;
  if hasFilter then begin
    for i := 0 to filterSigs.Count - 1 do begin
      sig := filterSigs[i];
      group := GroupBySignature(pluginFile, sig);
      if not Assigned(group) then Continue;
      recCount := ElementCount(group);
      for j := 0 to recCount - 1 do begin
        rec := ElementByIndex(group, j);
        if Signature(rec) = 'GRUP' then Continue;
        edid := EditorID(rec);
        if emittedOne then results := results + ',';
        results := results + '{';
        results := results + '"sig":' + Esc(Signature(rec));
        results := results + ',"fid":' + Esc(IntToHex(GetLoadOrderFormID(rec), 8));
        results := results + ',"edid":' + Esc(edid);
        results := results + '}';
        emittedOne := True;
      end;
    end;
  end else begin
    groupCount := ElementCount(pluginFile);
    for i := 0 to groupCount - 1 do begin
      group := ElementByIndex(pluginFile, i);
      sig := Signature(group);
      if sig = '' then sig := Name(group);
      recCount := ElementCount(group);
      for j := 0 to recCount - 1 do begin
        rec := ElementByIndex(group, j);
        if Signature(rec) = 'GRUP' then Continue;
        edid := EditorID(rec);
        if emittedOne then results := results + ',';
        results := results + '{';
        results := results + '"sig":' + Esc(Signature(rec));
        results := results + ',"fid":' + Esc(IntToHex(GetLoadOrderFormID(rec), 8));
        results := results + ',"edid":' + Esc(edid);
        results := results + '}';
        emittedOne := True;
      end;
    end;
  end;

  buf := '{"target":' + Esc(target) + ',"results":[' + results + ']}';
  WriteOutput(outPath, buf);
  filterSigs.Free;
end;

end.
