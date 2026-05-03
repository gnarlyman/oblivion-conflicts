{
  references_to.pas - find every record that references any of the
  given FormIDs.

  Args:
    --formid=<hex> (one or more)   required
    --out=<path>                   required

  For each target FormID, walks ReferencedByCount/ReferencedByIndex on
  the master record and emits the referencing record's plugin, sig, fid,
  edid.
}
unit UserScript;

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

function GetArgs(const key: string): TStringList;
var
  i: integer;
  prefix, s: string;
begin
  Result := TStringList.Create;
  prefix := '--' + key + '=';
  for i := 0 to ParamCount do begin
    s := ParamStr(i);
    if Copy(s, 1, Length(prefix)) = prefix then
      Result.Add(Copy(s, Length(prefix) + 1, Length(s)));
  end;
end;

function ParseFormID(const s: string): cardinal;
var body: string;
begin
  body := s;
  if (Length(body) >= 2) and (Copy(body, 1, 2) = '0x') then
    body := Copy(body, 3, Length(body))
  else if (Length(body) >= 2) and (Copy(body, 1, 2) = '0X') then
    body := Copy(body, 3, Length(body));
  Result := StrToInt64('$' + body);
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

function LookupByLoFormID(fid: cardinal): IInterface;
var loIdx: integer; pluginFile: IInterface;
begin
  Result := nil;
  loIdx := (fid shr 24) and $FF;
  if loIdx >= FileCount then Exit;
  pluginFile := FileByLoadOrder(loIdx);
  if not Assigned(pluginFile) then Exit;
  Result := RecordByFormID(pluginFile, fid, False);
  if not Assigned(Result) then
    Result := RecordByFormID(pluginFile, fid, True);
end;

function RefsForRec(rec: IInterface): string;
var
  master, ref, refMain: IInterface;
  refCount, k: integer;
  buf: string;
  emittedOne: boolean;
begin
  master := MasterOrSelf(rec);
  refCount := ReferencedByCount(master);
  buf := '';
  emittedOne := False;
  for k := 0 to refCount - 1 do begin
    ref := ReferencedByIndex(master, k);
    if not Assigned(ref) then Continue;
    refMain := ContainingMainRecord(ref);
    if not Assigned(refMain) then refMain := ref;
    if emittedOne then buf := buf + ',';
    buf := buf + '{';
    buf := buf + '"plugin":' + Esc(GetFileName(GetFile(ref)));
    buf := buf + ',"sig":' + Esc(Signature(refMain));
    buf := buf + ',"fid":' + Esc(IntToHex(GetLoadOrderFormID(refMain), 8));
    buf := buf + ',"edid":' + Esc(EditorID(refMain));
    buf := buf + '}';
    emittedOne := True;
  end;
  Result := buf;
end;

function Initialize: integer;
var
  outPath, results, buf, refs: string;
  fids: TStringList;
  fid: cardinal;
  rec: IInterface;
  i: integer;
  emittedOne: boolean;
begin
  Result := 0;
  outPath := GetArg('out');
  fids := GetArgs('formid');

  if (outPath = '') or (fids.Count = 0) then begin
    WriteOutput('D:/Modlists/_clones/oblivion-conflicts/tests/.tmp/references_to_error.json',
                '{"error":"need --out and at least one --formid"}');
    fids.Free;
    Exit;
  end;

  results := '';
  emittedOne := False;
  for i := 0 to fids.Count - 1 do begin
    try fid := ParseFormID(fids[i]); except Continue; end;
    rec := LookupByLoFormID(fid);
    if not Assigned(rec) then Continue;
    refs := RefsForRec(rec);
    if emittedOne then results := results + ',';
    results := results + '{"target_fid":' + Esc(IntToHex(fid, 8))
            + ',"target_edid":' + Esc(EditorID(MasterOrSelf(rec)))
            + ',"refs":[' + refs + ']}';
    emittedOne := True;
  end;

  buf := '{"results":[' + results + ']}';
  WriteOutput(outPath, buf);
  fids.Free;
end;

end.
