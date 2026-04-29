{
  _probe_lib.pas — verifies the full set of inlined helpers under the
  patched headless binary. Throwaway; deleted once each query script
  inlines its own helper preamble.

  Helpers covered:
    Esc, ConflictName, GetArg, HasArg, GetArgs, ParseFormID,
    NowIso8601, WriteOutput, MetaContent

  Usage:
    "$OBLIVION_CONFLICTS_XEDIT" -IKnowWhatImDoing -autoload -autoexit \
      -D:tests/fixtures/data \
      -P:tests/fixtures/loadorder.txt \
      -script:scripts/_probe_lib.pas \
      --out=tests/.tmp/probe_lib.json \
      --target=MOO.esp \
      --formid=0x1E012345 --formid=DEADBEEF
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

function HasArg(const key: string): boolean;
var
  i: integer;
  prefix, s: string;
begin
  Result := False;
  prefix := '--' + key + '=';
  for i := 0 to ParamCount do begin
    s := ParamStr(i);
    if Copy(s, 1, Length(prefix)) = prefix then begin
      Result := True;
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

function Initialize: integer;
var
  outPath, buf, errMsg, args, startedAt: string;
  startD: TDateTime;
  fids: TStringList;
  i, durationMs: integer;
begin
  Result := 0;
  errMsg := '';
  startD := Now;
  startedAt := NowIso8601;

  buf := '{';
  try
    // String escape
    buf := buf + '"esc_simple":' + Esc('hello');
    buf := buf + ',"esc_quotes":' + Esc('a"b');
    buf := buf + ',"esc_backslash":' + Esc('a\b');
    buf := buf + ',"esc_path":' + Esc('C:\Modlists\test');
    buf := buf + ',"esc_newline":' + Esc('line1' + #13#10 + 'line2');
    buf := buf + ',"esc_tab":' + Esc('a' + #9 + 'b');

    // Conflict-status enum
    buf := buf + ',"conflict_names":[';
    for i := 0 to 6 do begin
      if i > 0 then buf := buf + ',';
      buf := buf + Esc(ConflictName(i));
    end;
    buf := buf + ']';

    // Argument parsing
    buf := buf + ',"arg_target":' + Esc(GetArg('target'));
    buf := buf + ',"has_target":';
    if HasArg('target') then buf := buf + 'true' else buf := buf + 'false';
    buf := buf + ',"arg_missing":' + Esc(GetArg('does_not_exist'));
    buf := buf + ',"has_missing":';
    if HasArg('does_not_exist') then buf := buf + 'true' else buf := buf + 'false';

    fids := GetArgs('formid');
    try
      buf := buf + ',"formid_count":' + IntToStr(fids.Count);
      buf := buf + ',"formids":[';
      for i := 0 to fids.Count - 1 do begin
        if i > 0 then buf := buf + ',';
        buf := buf + Esc(fids[i]);
      end;
      buf := buf + ']';
      buf := buf + ',"formids_parsed":[';
      for i := 0 to fids.Count - 1 do begin
        if i > 0 then buf := buf + ',';
        buf := buf + Esc(IntToHex(ParseFormID(fids[i]), 8));
      end;
      buf := buf + ']';
    finally
      fids.Free;
    end;

    // MetaContent / NowIso8601 / load order
    args := '{"target":' + Esc(GetArg('target')) +
            ',"out":' + Esc(GetArg('out')) + '}';
    durationMs := Round((Now - startD) * 86400000);
    buf := buf + ',"meta_sample":' +
           MetaContent('probe', args, startedAt, durationMs);
  except
    on E: Exception do errMsg := E.Message;
  end;
  buf := buf + ',"error":' + Esc(errMsg) + '}';

  outPath := GetArg('out');
  if outPath = '' then outPath := 'D:/Modlists/_clones/oblivion-conflicts/tests/.tmp/probe_lib.json';

  WriteOutput(outPath, buf);
end;

end.
