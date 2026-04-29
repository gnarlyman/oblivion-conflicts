{
  _probe_lib.pas — verifies that the inlined helpers (Esc, ConflictName)
  produce the expected JSON output under the patched headless binary.

  Note: the original v2 plan envisioned a shared `obc_lib.pas` unit consumed
  via `uses obc_lib;`. JvInterpreter resolves `uses` from the process cwd /
  wbScriptsPath (xEdit install's Edit Scripts/), NOT from the directory
  containing the -script: argument. So the shared-unit model would require
  polluting the xEdit install. Inlining is simpler and self-contained.

  Usage:
    "$OBLIVION_CONFLICTS_XEDIT" -IKnowWhatImDoing -autoload -autoexit \
      -D:tests/fixtures/data \
      -P:tests/fixtures/loadorder.txt \
      -script:scripts/_probe_lib.pas \
      --out=tests/.tmp/probe_lib.json
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

function FindOutArg: string;
var i: integer; s: string;
begin
  Result := '';
  for i := 0 to ParamCount do begin
    s := ParamStr(i);
    if Copy(s, 1, 6) = '--out=' then begin
      Result := Copy(s, 7, Length(s));
      Exit;
    end;
  end;
end;

function Initialize: integer;
var
  outPath, buf, errMsg: string;
  sl: TStringList;
  i: integer;
begin
  Result := 0;
  errMsg := '';
  buf := '{';
  try
    buf := buf + '"esc_simple":' + Esc('hello');
    buf := buf + ',"esc_quotes":' + Esc('a"b');
    buf := buf + ',"esc_backslash":' + Esc('a\b');
    buf := buf + ',"esc_path":' + Esc('C:\Modlists\test');
    buf := buf + ',"esc_newline":' + Esc('line1' + #13#10 + 'line2');
    buf := buf + ',"esc_tab":' + Esc('a' + #9 + 'b');
    buf := buf + ',"conflict_names":[';
    for i := 0 to 6 do begin
      if i > 0 then buf := buf + ',';
      buf := buf + Esc(ConflictName(i));
    end;
    buf := buf + ']';
  except
    on E: Exception do errMsg := E.Message;
  end;
  buf := buf + ',"error":' + Esc(errMsg) + '}';

  outPath := FindOutArg;
  if outPath = '' then outPath := 'D:/Modlists/_clones/oblivion-conflicts/tests/.tmp/probe_lib.json';

  sl := TStringList.Create;
  try
    sl.Text := buf;
    sl.SaveToFile(outPath);
  finally
    sl.Free;
  end;
end;

end.
