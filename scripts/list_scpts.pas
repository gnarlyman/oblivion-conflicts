{
  list_scpts.pas - list all SCPT records in --target plugin with their
  EDID and a snippet of SCTX so you can see what scripts a plugin owns
  or overrides.

  Args:
    --target=plugin.esp     plugin to scan
    --out=path              output text
}
unit UserScript;

function GetArg(const key: string): string;
var i: Integer; prefix, s: string;
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

function FindFileByName(const name: string): IInterface;
var i: Integer; f: IInterface;
begin
  Result := nil;
  for i := 0 to Pred(FileCount) do begin
    f := FileByIndex(i);
    if SameText(GetFileName(f), name) then begin
      Result := f; Exit;
    end;
  end;
end;

function Initialize: Integer;
var
  target, outPath: string;
  f, rec, sctx: IInterface;
  i, totalRecs, count: Integer;
  out_: TStringList;
  edid, snippet, sctxStr: string;
begin
  target := GetArg('target');
  outPath := GetArg('out');
  if (target = '') or (outPath = '') then begin
    AddMessage('Usage: list_scpts --target=plugin.esp --out=path');
    Result := 1; Exit;
  end;
  f := FindFileByName(target);
  if not Assigned(f) then begin
    AddMessage('ERROR: target not loaded: ' + target);
    Result := 1; Exit;
  end;

  out_ := TStringList.Create;
  out_.Add('# SCPT records in ' + target);
  count := 0;

  totalRecs := RecordCount(f);
  for i := 0 to Pred(totalRecs) do begin
    rec := RecordByIndex(f, i);
    if Signature(rec) <> 'SCPT' then Continue;
    edid := EditorID(rec);
    sctx := ElementByPath(rec, 'SCTX');
    if Assigned(sctx) then begin
      sctxStr := GetEditValue(sctx);
      if Length(sctxStr) > 200 then snippet := Copy(sctxStr, 1, 200) + '...'
      else snippet := sctxStr;
    end else begin
      snippet := '<no SCTX>';
      sctxStr := '';
    end;
    out_.Add('---');
    out_.Add('EDID: ' + edid);
    out_.Add('FormID: ' + IntToHex(GetLoadOrderFormID(rec), 8));
    out_.Add('SCTX-len: ' + IntToStr(Length(sctxStr)));
    sctxStr := GetEditValue(ElementByPath(rec, 'SCHR\Compiled Size'));
    out_.Add('SCDA-len-from-SCHR: ' + sctxStr);
    out_.Add('Snippet: ' + Copy(snippet, 1, 80));
    Inc(count);
  end;

  out_.Add('');
  out_.Add('# Total SCPT records: ' + IntToStr(count));
  out_.SaveToFile(outPath);
  AddMessage('Wrote ' + IntToStr(count) + ' SCPT records to ' + outPath);
  out_.Free;
  Result := 0;
end;

end.
