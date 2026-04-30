{
  dump_chain_subrecord.pas - locate records by EDID inside --target plugin
  and dump a single subrecord (default SCTX) across every link in the
  override chain. Returns full chain values so you can compare what each
  patch did.

  Args:
    --target=plugin.esp       required (the plugin we walk to find records)
    --edid=editorid           required (one or more)
    --sub=subrecord-sig       optional (defaults to SCTX)
    --out=path                required

  Output: JSON envelope identical in shape to other oblivion-conflicts
  queries. results[] entries carry target_lo_formid_hex, edid, signature,
  sub, and chain[] with one plugin/edit_value pair per chain link.

  IMPORTANT: do not place curly braces of any kind inside this block
  comment - JvInterpreter ends the comment at the first close-brace and
  the leftover text reaches the parser as code.
}
unit UserScript;

const
  TOOL_VERSION = '0.1.0';

function Esc(const s: string): string;
begin
  Result := StringReplace(s, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
  Result := StringReplace(Result, #8, '\b', [rfReplaceAll]);
  Result := StringReplace(Result, #12, '\f', [rfReplaceAll]);
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

function NowIso8601: string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', Now);
end;

procedure WriteOutput(const path, content: string);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := content;
    sl.SaveToFile(path);
  finally
    sl.Free;
  end;
end;

function MetaContent(const argsJson, startedAt: string;
                     durationMs: integer): string;
var
  i: integer;
  loStr, xeditVer: string;
begin
  loStr := '';
  for i := 0 to FileCount - 1 do begin
    if i > 0 then loStr := loStr + ',';
    loStr := loStr + Esc(GetFileName(FileByLoadOrder(i)));
  end;
  xeditVer := '';
  try
    xeditVer := wbVersionNumber;
  except
    xeditVer := '';
  end;
  Result := '{';
  Result := Result + '"tool_version":' + Esc(TOOL_VERSION);
  if xeditVer <> '' then
    Result := Result + ',"xedit_version":' + Esc(xeditVer);
  Result := Result + ',"query":"dump_chain_subrecord"';
  Result := Result + ',"args":' + argsJson;
  Result := Result + ',"load_order":[' + loStr + ']';
  Result := Result + ',"started_at":' + Esc(startedAt);
  Result := Result + ',"duration_ms":' + IntToStr(durationMs);
  Result := Result + '}';
end;

function GetSubEditValue(rec: IInterface; const sig: string): string;
var
  elem: IInterface;
begin
  Result := '';
  elem := ElementBySignature(rec, sig);
  if not Assigned(elem) then
    elem := ElementByName(rec, sig);
  if not Assigned(elem) then Exit;
  Result := GetEditValue(elem);
end;

function ChainDumpJson(master: IInterface; ovrCount: integer;
                       const sub: string): string;
var
  i: integer;
  link: IInterface;
  pluginName, val: string;
begin
  pluginName := GetFileName(GetFile(master));
  val := GetSubEditValue(master, sub);
  Result := '{"plugin":' + Esc(pluginName) + ',"edit_value":' + Esc(val) + '}';
  for i := 0 to ovrCount - 1 do begin
    link := OverrideByIndex(master, i);
    pluginName := GetFileName(GetFile(link));
    val := GetSubEditValue(link, sub);
    Result := Result + ',{"plugin":' + Esc(pluginName) + ',"edit_value":' + Esc(val) + '}';
  end;
end;

function RecordEntry(rec: IInterface; const sub: string): string;
var
  master: IInterface;
  ovrCount: integer;
begin
  master := MasterOrSelf(rec);
  ovrCount := OverrideCount(master);
  Result := '{';
  Result := Result + '"target_lo_formid_hex":' + Esc(IntToHex(GetLoadOrderFormID(rec), 8));
  Result := Result + ',"edid":' + Esc(EditorID(rec));
  Result := Result + ',"signature":' + Esc(Signature(rec));
  Result := Result + ',"sub":' + Esc(sub);
  Result := Result + ',"chain":[' + ChainDumpJson(master, ovrCount, sub) + ']';
  Result := Result + '}';
end;

function BuildArgsJson(const target, sub, outPath: string;
                       edids: TStringList): string;
var i: integer;
begin
  Result := '{"target":' + Esc(target) + ',"sub":' + Esc(sub);
  Result := Result + ',"edid":[';
  for i := 0 to edids.Count - 1 do begin
    if i > 0 then Result := Result + ',';
    Result := Result + Esc(edids[i]);
  end;
  Result := Result + '],"out":' + Esc(outPath) + '}';
end;

function ErrorEnvelope(const argsJson, startedAt: string;
                      durationMs: integer;
                      const code, msg: string): string;
begin
  Result := '{';
  Result := Result + '"meta":' + MetaContent(argsJson, startedAt, durationMs);
  Result := Result + ',"error":{"code":' + Esc(code) + ',"message":' + Esc(msg) + '}';
  Result := Result + '}';
end;

function Initialize: integer;
var
  target, sub, outPath, args, startedAt, results, buf, errMsg, recEdid: string;
  edids: TStringList;
  startD: TDateTime;
  durationMs, i, j, found: integer;
  pluginFile, rec: IInterface;
  emittedOne, foundFile: boolean;
begin
  Result := 0;
  startD := Now;
  startedAt := NowIso8601;

  outPath := GetArg('out');
  target  := GetArg('target');
  sub     := GetArg('sub');
  if sub = '' then sub := 'SCTX';
  edids   := GetArgs('edid');
  args    := BuildArgsJson(target, sub, outPath, edids);

  if outPath = '' then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(
      'D:/Modlists/_clones/oblivion-conflicts/tests/.tmp/dump_chain_error.json',
      ErrorEnvelope(args, startedAt, durationMs, 'missing_arg', '--out is required'));
    edids.Free;
    Exit;
  end;

  if target = '' then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(outPath, ErrorEnvelope(args, startedAt, durationMs,
      'missing_arg', '--target is required'));
    edids.Free;
    Exit;
  end;

  if edids.Count = 0 then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(outPath, ErrorEnvelope(args, startedAt, durationMs,
      'missing_arg', '--edid is required (one or more)'));
    edids.Free;
    Exit;
  end;

  foundFile := False;
  for i := 0 to FileCount - 1 do begin
    pluginFile := FileByLoadOrder(i);
    if SameText(GetFileName(pluginFile), target) then begin
      foundFile := True;
      Break;
    end;
  end;

  if not foundFile then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(outPath, ErrorEnvelope(args, startedAt, durationMs,
      'plugin_not_loaded', 'plugin not in load order: ' + target));
    edids.Free;
    Exit;
  end;

  results := '';
  emittedOne := False;
  found := 0;
  errMsg := '';
  try
    for i := 0 to RecordCount(pluginFile) - 1 do begin
      rec := RecordByIndex(pluginFile, i);
      if Signature(rec) = 'TES4' then Continue;
      recEdid := EditorID(rec);
      if recEdid = '' then Continue;
      for j := 0 to edids.Count - 1 do begin
        if SameText(recEdid, edids[j]) then begin
          if emittedOne then results := results + ',';
          results := results + RecordEntry(rec, sub);
          emittedOne := True;
          Inc(found);
          Break;
        end;
      end;
    end;
  except
    on E: Exception do errMsg := E.Message;
  end;

  durationMs := Round((Now - startD) * 86400000);

  if errMsg <> '' then begin
    WriteOutput(outPath, ErrorEnvelope(args, startedAt, durationMs,
      'xedit_internal', errMsg));
    edids.Free;
    Exit;
  end;

  buf := '{';
  buf := buf + '"meta":' + MetaContent(args, startedAt, durationMs);
  buf := buf + ',"results":[' + results + ']';
  buf := buf + '}';
  WriteOutput(outPath, buf);
  edids.Free;
end;

end.
