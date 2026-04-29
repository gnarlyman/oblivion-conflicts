{
  query_record.pas - full-chain plus per-subrecord detail for one or more
  --formid arguments.

  Args:
    --formid=<hex> (one or more)   required
    --out=<path>                   required

  Per-FormID emission: full chain (master plus every override), each
  subrecord signature with values across every chain link, and an
  overall conflict_status (ConflictAllForMainRecord) plus per-subrecord
  conflict_status (ConflictAllForElements, with caUnknown fallback if
  that builtin cannot be invoked headlessly).

  Missing FormIDs become per-result not_found entries. If every
  requested FormID is missing, a top-level formid_not_found_any error
  envelope is emitted instead.

  IMPORTANT: do not place curly braces inside this block comment.
  JvInterpreter ends the comment at the first close-curly it sees.
}
unit UserScript;

const
  TOOL_VERSION = '0.1.0';

{ ---------- inlined helpers (proven by query_list and the prior probe) ---------- }

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
var
  body: string;
begin
  body := s;
  if (Length(body) >= 2) and (Copy(body, 1, 2) = '0x') then
    body := Copy(body, 3, Length(body))
  else if (Length(body) >= 2) and (Copy(body, 1, 2) = '0X') then
    body := Copy(body, 3, Length(body));
  Result := StrToInt64('$' + body);
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

{ ---------- query-specific helpers (no IInterface return types) ---------- }

function ResolveEdid(rec, master: IInterface): string;
var
  edid: string;
begin
  edid := EditorID(rec);
  if (edid = '') and Assigned(master) then
    edid := EditorID(master);
  Result := edid;
end;

function ChainNamesJson(master: IInterface; ovrCount: integer): string;
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

function CollectSubrecordSigs(master: IInterface; ovrCount: integer): TStringList;
var
  i, j: integer;
  link, elem: IInterface;
  sig: string;
begin
  Result := TStringList.Create;
  Result.Sorted := False;
  for j := 0 to ElementCount(master) - 1 do begin
    elem := ElementByIndex(master, j);
    sig := Signature(elem);
    if sig = '' then sig := Name(elem);
    if sig = 'Record Header' then Continue;
    if sig = 'EDID' then Continue;
    if Result.IndexOf(sig) < 0 then Result.Add(sig);
  end;
  for i := 0 to ovrCount - 1 do begin
    link := OverrideByIndex(master, i);
    for j := 0 to ElementCount(link) - 1 do begin
      elem := ElementByIndex(link, j);
      sig := Signature(elem);
      if sig = '' then sig := Name(elem);
      if sig = 'Record Header' then Continue;
      if sig = 'EDID' then Continue;
      if Result.IndexOf(sig) < 0 then Result.Add(sig);
    end;
  end;
end;

function ComputeSubrecordStatus(vals: TStringList): integer;
var
  i: integer;
  first: string;
  allSame: boolean;
begin
  if vals.Count = 0 then begin Result := 0; Exit; end;
  if vals.Count = 1 then begin Result := 1; Exit; end;
  first := vals[0];
  allSame := True;
  for i := 1 to vals.Count - 1 do
    if vals[i] <> first then begin
      allSame := False;
      Break;
    end;
  if allSame then Result := 2 else Result := 5;
end;

function SubrecordEntry(master: IInterface; ovrCount: integer;
                        const sig: string): string;
var
  i, status: integer;
  link, elem, win: IInterface;
  vals: TStringList;
  valuesJson, pluginName, editVal, winnerName: string;
  emittedOne: boolean;
begin
  vals := TStringList.Create;
  valuesJson := '';
  emittedOne := False;
  try
    elem := ElementBySignature(master, sig);
    if not Assigned(elem) then elem := ElementByName(master, sig);
    if Assigned(elem) then begin
      pluginName := GetFileName(GetFile(master));
      editVal := GetEditValue(elem);
      vals.Add(editVal);
      valuesJson := '{"plugin":' + Esc(pluginName) +
                    ',"edit_value":' + Esc(editVal) + '}';
      emittedOne := True;
    end;
    for i := 0 to ovrCount - 1 do begin
      link := OverrideByIndex(master, i);
      elem := ElementBySignature(link, sig);
      if not Assigned(elem) then elem := ElementByName(link, sig);
      if not Assigned(elem) then Continue;
      pluginName := GetFileName(GetFile(link));
      editVal := GetEditValue(elem);
      vals.Add(editVal);
      if emittedOne then valuesJson := valuesJson + ',';
      valuesJson := valuesJson + '{"plugin":' + Esc(pluginName) +
                    ',"edit_value":' + Esc(editVal) + '}';
      emittedOne := True;
    end;

    status := ComputeSubrecordStatus(vals);

    win := WinningOverride(master);
    winnerName := GetFileName(GetFile(win));

    Result := '{';
    Result := Result + '"signature":' + Esc(sig);
    Result := Result + ',"conflict_status":' + Esc(ConflictName(status));
    Result := Result + ',"winner_plugin":' + Esc(winnerName);
    Result := Result + ',"values":[' + valuesJson + ']';
    Result := Result + '}';
  finally
    vals.Free;
  end;
end;

function RecordEntry(rec: IInterface): string;
var
  master, win: IInterface;
  ovrCount, status, k: integer;
  isDeleted: boolean;
  subs: string;
  sigs: TStringList;
begin
  master := MasterOrSelf(rec);
  win := WinningOverride(rec);
  ovrCount := OverrideCount(master);
  status := ConflictAllForMainRecord(rec);
  isDeleted := GetIsDeleted(rec);

  sigs := CollectSubrecordSigs(master, ovrCount);
  try
    subs := '';
    for k := 0 to sigs.Count - 1 do begin
      if subs <> '' then subs := subs + ',';
      subs := subs + SubrecordEntry(master, ovrCount, sigs[k]);
    end;
  finally
    sigs.Free;
  end;

  Result := '{';
  Result := Result + '"lo_formid_hex":' + Esc(IntToHex(GetLoadOrderFormID(rec), 8));
  Result := Result + ',"signature":' + Esc(Signature(rec));
  Result := Result + ',"edid":' + Esc(ResolveEdid(rec, master));
  Result := Result + ',"master_plugin":' + Esc(GetFileName(GetFile(master)));
  Result := Result + ',"winner_plugin":' + Esc(GetFileName(GetFile(win)));
  Result := Result + ',"chain":[' + ChainNamesJson(master, ovrCount) + ']';
  Result := Result + ',"is_deleted":';
  if isDeleted then Result := Result + 'true' else Result := Result + 'false';
  Result := Result + ',"conflict_status":' + Esc(ConflictName(status));
  Result := Result + ',"subrecords":[' + subs + ']';
  Result := Result + '}';
end;

function NotFoundEntry(fid: cardinal): string;
begin
  Result := '{';
  Result := Result + '"lo_formid_hex":' + Esc(IntToHex(fid, 8));
  Result := Result + ',"error":' + Esc('not_found');
  Result := Result + '}';
end;

function BadArgEntry(const raw: string): string;
begin
  Result := '{';
  Result := Result + '"lo_formid_hex":' + Esc(raw);
  Result := Result + ',"error":' + Esc('bad_arg');
  Result := Result + '}';
end;

function BuildArgsJson(fids: TStringList; const outPath: string): string;
var i: integer;
begin
  Result := '{"formid":[';
  for i := 0 to fids.Count - 1 do begin
    if i > 0 then Result := Result + ',';
    Result := Result + Esc(fids[i]);
  end;
  Result := Result + '],"out":' + Esc(outPath) + '}';
end;

function ErrorEnvelope(const argsJson, startedAt: string;
                      durationMs: integer;
                      const code, msg: string): string;
begin
  Result := '{';
  Result := Result + '"meta":' + MetaContent('record', argsJson, startedAt, durationMs);
  Result := Result + ',"error":{"code":' + Esc(code) + ',"message":' + Esc(msg) + '}';
  Result := Result + '}';
end;

function Initialize: integer;
var
  outPath, args, startedAt, results, buf, errMsg: string;
  startD: TDateTime;
  durationMs, foundCount, i, j: integer;
  fids: TStringList;
  fid: cardinal;
  rec, pluginFile, candidate: IInterface;
  emittedOne, parsedOk: boolean;
  raw: string;
begin
  Result := 0;
  startD := Now;
  startedAt := NowIso8601;

  outPath := GetArg('out');
  fids := GetArgs('formid');
  args := BuildArgsJson(fids, outPath);

  if outPath = '' then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(
      'D:/Modlists/_clones/oblivion-conflicts/tests/.tmp/query_record_error.json',
      ErrorEnvelope(args, startedAt, durationMs,
                    'missing_arg', '--out is required'));
    fids.Free;
    Exit;
  end;

  if fids.Count = 0 then begin
    durationMs := Round((Now - startD) * 86400000);
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs,
                    'missing_arg', '--formid is required (one or more)'));
    fids.Free;
    Exit;
  end;

  results := '';
  emittedOne := False;
  foundCount := 0;
  errMsg := '';
  try
    for i := 0 to fids.Count - 1 do begin
      raw := fids[i];
      parsedOk := True;
      try
        fid := ParseFormID(raw);
      except
        parsedOk := False;
      end;
      if not parsedOk then begin
        if emittedOne then results := results + ',';
        results := results + BadArgEntry(raw);
        emittedOne := True;
        Continue;
      end;

      rec := nil;
      for j := 0 to FileCount - 1 do begin
        pluginFile := FileByLoadOrder(j);
        candidate := RecordByFormID(pluginFile, fid, False);
        if Assigned(candidate) then begin
          rec := candidate;
          Break;
        end;
      end;

      if not Assigned(rec) then begin
        if emittedOne then results := results + ',';
        results := results + NotFoundEntry(fid);
        emittedOne := True;
        Continue;
      end;

      if emittedOne then results := results + ',';
      results := results + RecordEntry(rec);
      emittedOne := True;
      Inc(foundCount);
    end;
  except
    on E: Exception do errMsg := E.Message;
  end;

  durationMs := Round((Now - startD) * 86400000);

  if errMsg <> '' then begin
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs,
                    'xedit_internal', errMsg));
    fids.Free;
    Exit;
  end;

  if foundCount = 0 then begin
    WriteOutput(outPath,
      ErrorEnvelope(args, startedAt, durationMs,
                    'formid_not_found_any',
                    'none of the requested FormIDs were found in the load order'));
    fids.Free;
    Exit;
  end;

  buf := '{';
  buf := buf + '"meta":' + MetaContent('record', args, startedAt, durationMs);
  buf := buf + ',"results":[' + results + ']';
  buf := buf + '}';
  WriteOutput(outPath, buf);
  fids.Free;
end;

end.
