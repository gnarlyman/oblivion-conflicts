{
  quest_flags.pas - read QUST DATA flag byte across the override chain.

  For each --formid, walks master + every override and emits the DATA -
  Quest Data\Flags edit_value (e.g. "Start Game Enabled, Allow Repeated
  Topics, ...").

  Args:
    --formid=<hex> (one or more)   required
    --out=<path>                   required
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

function LookupByLoFormID(fid: cardinal): IInterface;
var
  loIdx: integer;
  pluginFile: IInterface;
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

function ReadDataFlags(rec: IInterface): string;
var
  data, flags, priority: IInterface;
  res: string;
begin
  res := '';
  data := ElementBySignature(rec, 'DATA');
  if not Assigned(data) then begin Result := '<no DATA>'; Exit; end;

  flags := ElementByName(data, 'Flags');
  if Assigned(flags) then
    res := 'Flags=' + GetEditValue(flags)
  else
    res := 'Flags=<missing>';

  priority := ElementByName(data, 'Priority');
  if Assigned(priority) then
    res := res + ' Priority=' + GetEditValue(priority);

  Result := res;
end;

function ReadFromRec(rec: IInterface): string;
var
  master: IInterface;
  ovrCount, i: integer;
  link: IInterface;
  buf, sigBuf, edidBuf: string;
begin
  master := MasterOrSelf(rec);
  ovrCount := OverrideCount(master);

  sigBuf := Signature(rec);
  edidBuf := EditorID(master);
  if edidBuf = '' then edidBuf := EditorID(rec);

  buf := '';
  buf := buf + '{"lo_formid_hex":' + Esc(IntToHex(GetLoadOrderFormID(rec), 8));
  buf := buf + ',"signature":' + Esc(sigBuf);
  buf := buf + ',"edid":' + Esc(edidBuf);
  buf := buf + ',"data":[';
  buf := buf + '{"plugin":' + Esc(GetFileName(GetFile(master)))
            + ',"value":' + Esc(ReadDataFlags(master)) + '}';
  for i := 0 to ovrCount - 1 do begin
    link := OverrideByIndex(master, i);
    buf := buf + ',{"plugin":' + Esc(GetFileName(GetFile(link)))
              + ',"value":' + Esc(ReadDataFlags(link)) + '}';
  end;
  buf := buf + ']}';
  Result := buf;
end;

function Initialize: integer;
var
  outPath, results, buf: string;
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
    WriteOutput('D:/Modlists/_clones/oblivion-conflicts/tests/.tmp/quest_flags_error.json',
                '{"error":"need --out and at least one --formid"}');
    fids.Free;
    Exit;
  end;

  results := '';
  emittedOne := False;
  for i := 0 to fids.Count - 1 do begin
    try
      fid := ParseFormID(fids[i]);
    except
      Continue;
    end;
    rec := LookupByLoFormID(fid);
    if not Assigned(rec) then Continue;
    if emittedOne then results := results + ',';
    results := results + ReadFromRec(rec);
    emittedOne := True;
  end;

  buf := '{"results":[' + results + ']}';
  WriteOutput(outPath, buf);
  fids.Free;
end;

end.
