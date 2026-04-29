{
  query_list.pas - list every record in --target where xEdit detects a
  conflict status >= caOverride (anything someone else also touches).

  Args:
    --target=<plugin.esp>  required
    --out=<path>           required

  Output: JSON envelope with a meta object plus either results array or
  error object. See README for the schema.

  Helpers are inlined (no `uses obc_lib;`) because JvInterpreter resolves
  unit imports from the xEdit install Edit Scripts dir, not from the
  -script: argument directory.

  IMPORTANT: Pascal `(curly-brace)` block comments are NOT nestable in
  JvInterpreter. The first close-curly-brace ends the comment. Do not
  use curly braces inside any block comment in these scripts.
}
unit UserScript;

const
  TOOL_VERSION = '0.1.0';
  CA_OVERRIDE  = 4;

{ ---------- inlined helpers (proven via _probe_lib.pas) ---------- }

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

function ConflictName(c: integer): string;
begin
  case c of
    0: Result := 'caUnknown';
    1: Result := 'caOnlyOne';
    2: Result := 'caNoConflict';
    3: Result := 'caConflictBenign';
    4: Result := 'caOverride';
    5: Result := 'caConflict';
    6: Result := 'caConflictCritical';
  else
    Result := 'caUnknown';
  end;
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

function MetaContent(const query, argsJson, startedAt: string;
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
  Result := Result + ',"query":' + Esc(query);
  Result := Result + ',"args":' + argsJson;
  Result := Result + ',"load_order":[' + loStr + ']';
  Result := Result + ',"started_at":' + Esc(startedAt);
  Result := Result + ',"duration_ms":' + IntToStr(durationMs);
  Result := Result + '}';
end;

{ ---------- query-specific helpers ---------- }

function ChainList(master: IInterface; ovrCount: integer): string;
var
  i: integer;
  link: IInterface;
begin
  Result := Esc(GetFileName(GetFile(master)));
  for i := 0 to ovrCount - 1 do begin
    link := OverrideByIndex(master, i);
    Result := Result + ',' + Esc(GetFileName(GetFile(link)));
  end;
end;

function ResolveEdid(rec, master: IInterface): string;
var
  edid: string;
begin
  { Deleted overrides lose EDID; fall back to master EDID. }
  edid := EditorID(rec);
  if (edid = '') and Assigned(master) then
    edid := EditorID(master);
  Result := edid;
end;

function IsInjected(master: IInterface): boolean;
var
  masterFile: IInterface;
  expected, actual: cardinal;
begin
  { Compare load-order index encoded in the record FormID against the
    file MasterOrSelf returned. Mismatch indicates injection. }
  Result := False;
  if not Assigned(master) then Exit;
  masterFile := GetFile(master);
  if not Assigned(masterFile) then Exit;
  expected := GetLoadOrder(masterFile);
  actual := GetLoadOrderFormID(master) shr 24;
  Result := expected <> actual;
end;

function RecordEntry(rec: IInterface): string;
var
  master, win: IInterface;
  ovrCount, status: integer;
  isWinner, isDeleted, injected: boolean;
begin
  master    := MasterOrSelf(rec);
  win       := WinningOverride(rec);
  ovrCount  := OverrideCount(master);
  status    := ConflictAllForMainRecord(rec);
  isWinner  := SameText(GetFileName(GetFile(rec)), GetFileName(GetFile(win)));
  isDeleted := GetIsDeleted(rec);
  injected  := IsInjected(master);

  Result := '{';
  Result := Result + '"lo_formid_hex":' + Esc(IntToHex(GetLoadOrderFormID(rec), 8));
  Result := Result + ',"signature":' + Esc(Signature(rec));
  Result := Result + ',"edid":' + Esc(ResolveEdid(rec, master));
  Result := Result + ',"master_plugin":' + Esc(GetFileName(GetFile(master)));
  Result := Result + ',"winner_plugin":' + Esc(GetFileName(GetFile(win)));
  Result := Result + ',"is_winner":';
  if isWinner then Result := Result + 'true' else Result := Result + 'false';
  Result := Result + ',"is_deleted":';
  if isDeleted then Result := Result + 'true' else Result := Result + 'false';
  Result := Result + ',"is_injected":';
  if injected then Result := Result + 'true' else Result := Result + 'false';
  Result := Result + ',"conflict_status":' + Esc(ConflictName(status));
  Result := Result + ',"chain":[' + ChainList(master, ovrCount) + ']';
  Result := Result + '}';
end;

function BuildArgsJson(const target, outPath: string): string;
begin
  Result := '{"target":' + Esc(target) + ',"out":' + Esc(outPath) + '}';
end;

function ErrorEnvelope(const argsJson, startedAt: string;
                      durationMs: integer;
                      const code, msg: string): string;
begin
  Result := '{';
  Result := Result + '"meta":' + MetaContent('list', argsJson, startedAt, durationMs);
  Result := Result + ',"error":{"code":' + Esc(code) + ',"message":' + Esc(msg) + '}';
  Result := Result + '}';
end;

function Initialize: integer;
var
  target, outPath, startedAt, errMsg, args, results, buf, pluginName: string;
  startD: TDateTime;
  durationMs, status, recordsEmitted, i: integer;
  pluginFile, rec: IInterface;
  emittedOne, found: boolean;
begin
  Result := 0;
  startD := Now;
  startedAt := NowIso8601;

  outPath := GetArg('out');
  target  := GetArg('target');
  args    := BuildArgsJson(target, outPath);

  if outPath = '' then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(
      'D:/Modlists/_clones/oblivion-conflicts/tests/.tmp/query_list_error.json',
      ErrorEnvelope(args, startedAt, durationMs,
                    'missing_arg', '--out is required'));
    Exit;
  end;

  if target = '' then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs,
                    'missing_arg', '--target is required'));
    Exit;
  end;

  { Find target plugin (inlined to avoid IInterface return type, which
    JvInterpreter may not handle reliably). }
  found := False;
  for i := 0 to FileCount - 1 do begin
    pluginFile := FileByLoadOrder(i);
    pluginName := GetFileName(pluginFile);
    if SameText(pluginName, target) then begin
      found := True;
      Break;
    end;
  end;

  if not found then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs,
                    'plugin_not_loaded',
                    'plugin not in load order: ' + target));
    Exit;
  end;

  results := '';
  recordsEmitted := 0;
  emittedOne := False;
  errMsg := '';
  try
    for i := 0 to RecordCount(pluginFile) - 1 do begin
      rec := RecordByIndex(pluginFile, i);
      if Signature(rec) = 'TES4' then Continue;
      status := ConflictAllForMainRecord(rec);
      if status < CA_OVERRIDE then Continue;
      if emittedOne then results := results + ',';
      results := results + RecordEntry(rec);
      Inc(recordsEmitted);
      emittedOne := True;
    end;
  except
    on E: Exception do errMsg := E.Message;
  end;

  durationMs := Round((Now - startD) * 86400000);

  if errMsg <> '' then begin
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs,
                    'xedit_internal', errMsg));
    Exit;
  end;

  buf := '{';
  buf := buf + '"meta":' + MetaContent('list', args, startedAt, durationMs);
  buf := buf + ',"results":[' + results + ']';
  buf := buf + '}';
  WriteOutput(outPath, buf);
end;

end.
