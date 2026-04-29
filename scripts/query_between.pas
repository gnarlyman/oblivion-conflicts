{
  query_between.pas - list every record both --a and --b touch within
  the same load order. Per-subrecord conflict_status comes from a local
  edit_value comparison (ConflictAllForElements is unreachable from
  headless JvInterpreter scripts, see memory feedback_pascal_script_quirks).

  Args:
    --a=<plugin.esp>   required
    --b=<plugin.esp>   required
    --out=<path>       required

  Output: JSON envelope with meta plus either results array or error
  object. results contains one entry per record both A and B touch,
  with a short summary string from each side (GetSummary, falls back to
  empty string) and a subrecords array listing the union of top-level
  subrecord signatures with a per-signature conflict_status.

  IMPORTANT: do not place curly braces inside this block comment.
}
unit UserScript;

const
  TOOL_VERSION = '0.1.0';

{ ---------- inlined helpers ---------- }

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

function GetSummarySafe(rec: IInterface): string;
begin
  Result := '';
  try
    Result := GetSummary(rec);
  except
    Result := '';
  end;
end;

function ComputeBetweenStatus(hasA, hasB: boolean;
                              const valA, valB: string): integer;
begin
  if hasA and hasB then begin
    if valA = valB then Result := 2 else Result := 5;
  end else if hasA or hasB then
    Result := 4
  else
    Result := 0;
end;

function CollectUnionSigs(recA, recB: IInterface): TStringList;
var
  i: integer;
  elem: IInterface;
  sig: string;
begin
  Result := TStringList.Create;
  Result.Sorted := False;
  for i := 0 to ElementCount(recA) - 1 do begin
    elem := ElementByIndex(recA, i);
    sig := Signature(elem);
    if sig = '' then sig := Name(elem);
    if sig = 'Record Header' then Continue;
    if sig = 'EDID' then Continue;
    if Result.IndexOf(sig) < 0 then Result.Add(sig);
  end;
  for i := 0 to ElementCount(recB) - 1 do begin
    elem := ElementByIndex(recB, i);
    sig := Signature(elem);
    if sig = '' then sig := Name(elem);
    if sig = 'Record Header' then Continue;
    if sig = 'EDID' then Continue;
    if Result.IndexOf(sig) < 0 then Result.Add(sig);
  end;
end;

function SubrecordEntry(recA, recB: IInterface; const sig: string): string;
var
  elemA, elemB: IInterface;
  hasA, hasB: boolean;
  valA, valB: string;
  status: integer;
begin
  elemA := ElementBySignature(recA, sig);
  if not Assigned(elemA) then elemA := ElementByName(recA, sig);
  elemB := ElementBySignature(recB, sig);
  if not Assigned(elemB) then elemB := ElementByName(recB, sig);

  hasA := Assigned(elemA);
  hasB := Assigned(elemB);
  if hasA then valA := GetEditValue(elemA) else valA := '';
  if hasB then valB := GetEditValue(elemB) else valB := '';

  status := ComputeBetweenStatus(hasA, hasB, valA, valB);

  Result := '{';
  Result := Result + '"signature":' + Esc(sig);
  Result := Result + ',"conflict_status":' + Esc(ConflictName(status));
  Result := Result + '}';
end;

function RecordEntry(recA, recB: IInterface): string;
var
  master, win: IInterface;
  sigs: TStringList;
  subs, sumA, sumB, edid: string;
  k: integer;
begin
  master := MasterOrSelf(recA);
  win := WinningOverride(master);
  sumA := GetSummarySafe(recA);
  sumB := GetSummarySafe(recB);

  edid := EditorID(master);
  if edid = '' then edid := EditorID(recA);

  sigs := CollectUnionSigs(recA, recB);
  try
    subs := '';
    for k := 0 to sigs.Count - 1 do begin
      if subs <> '' then subs := subs + ',';
      subs := subs + SubrecordEntry(recA, recB, sigs[k]);
    end;
  finally
    sigs.Free;
  end;

  Result := '{';
  Result := Result + '"lo_formid_hex":' + Esc(IntToHex(GetLoadOrderFormID(recA), 8));
  Result := Result + ',"signature":' + Esc(Signature(recA));
  Result := Result + ',"edid":' + Esc(edid);
  Result := Result + ',"winner_plugin":' + Esc(GetFileName(GetFile(win)));
  Result := Result + ',"a_summary":' + Esc(sumA);
  Result := Result + ',"b_summary":' + Esc(sumB);
  Result := Result + ',"subrecords":[' + subs + ']';
  Result := Result + '}';
end;

function BuildArgsJson(const a, b, outPath: string): string;
begin
  Result := '{"a":' + Esc(a) + ',"b":' + Esc(b) +
            ',"out":' + Esc(outPath) + '}';
end;

function ErrorEnvelope(const argsJson, startedAt: string;
                      durationMs: integer;
                      const code, msg: string): string;
begin
  Result := '{';
  Result := Result + '"meta":' + MetaContent('between', argsJson, startedAt, durationMs);
  Result := Result + ',"error":{"code":' + Esc(code) + ',"message":' + Esc(msg) + '}';
  Result := Result + '}';
end;

function Initialize: integer;
var
  aName, bName, outPath, args, startedAt, results, buf, errMsg, pluginName: string;
  startD: TDateTime;
  durationMs, i: integer;
  fileA, fileB, recA, recB, pluginFile: IInterface;
  emittedOne, foundA, foundB: boolean;
  fid: cardinal;
begin
  Result := 0;
  startD := Now;
  startedAt := NowIso8601;

  outPath := GetArg('out');
  aName := GetArg('a');
  bName := GetArg('b');
  args := BuildArgsJson(aName, bName, outPath);

  if outPath = '' then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(
      'D:/Modlists/_clones/oblivion-conflicts/tests/.tmp/query_between_error.json',
      ErrorEnvelope(args, startedAt, durationMs,
                    'missing_arg', '--out is required'));
    Exit;
  end;
  if (aName = '') or (bName = '') then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs,
                    'missing_arg', '--a and --b are both required'));
    Exit;
  end;

  fileA := nil;
  fileB := nil;
  foundA := False;
  foundB := False;
  for i := 0 to FileCount - 1 do begin
    pluginFile := FileByLoadOrder(i);
    pluginName := GetFileName(pluginFile);
    if SameText(pluginName, aName) then begin fileA := pluginFile; foundA := True; end;
    if SameText(pluginName, bName) then begin fileB := pluginFile; foundB := True; end;
  end;

  if not foundA then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs,
                    'plugin_not_loaded',
                    '--a plugin not in load order: ' + aName));
    Exit;
  end;
  if not foundB then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs,
                    'plugin_not_loaded',
                    '--b plugin not in load order: ' + bName));
    Exit;
  end;

  results := '';
  emittedOne := False;
  errMsg := '';
  try
    for i := 0 to RecordCount(fileA) - 1 do begin
      recA := RecordByIndex(fileA, i);
      if Signature(recA) = 'TES4' then Continue;
      fid := GetLoadOrderFormID(recA);
      recB := RecordByFormID(fileB, fid, False);
      if not Assigned(recB) then Continue;
      { RecordByFormID returns master-inherited records too; only count the
        record as shared if B owns its own override (GetFile points at B). }
      if not SameText(GetFileName(GetFile(recB)), bName) then Continue;
      if emittedOne then results := results + ',';
      results := results + RecordEntry(recA, recB);
      emittedOne := True;
    end;
  except
    on E: Exception do errMsg := E.Message;
  end;

  durationMs := Round((Now - startD) * 86400000);

  if errMsg <> '' then begin
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs, 'xedit_internal', errMsg));
    Exit;
  end;

  buf := '{';
  buf := buf + '"meta":' + MetaContent('between', args, startedAt, durationMs);
  buf := buf + ',"results":[' + results + ']';
  buf := buf + '}';
  WriteOutput(outPath, buf);
end;

end.
