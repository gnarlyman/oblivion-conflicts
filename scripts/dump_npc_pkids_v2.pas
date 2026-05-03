{
  dump_npc_pkids_v2.pas - find every PKID FormID reference inside
  the NPC record by walking the element tree until we hit elements
  whose Signature='PKID' or whose container Name='Packages'.

  Args:
    --target=plugin   plugin to scan
    --edid=editorid   NPC EDID
    --out=path        output JSON
}
unit UserScript;

const
  TOOL_VERSION = '0.2.0';

var
  gOut: TStringList;
  gPkidCount: Integer;

function Esc(const s: string): string;
begin
  Result := StringReplace(s, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
end;

function GetArg(const key: string): string;
var
  i: Integer;
  prefix, s: string;
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
var
  i: Integer;
  f: IInterface;
begin
  Result := nil;
  for i := 0 to Pred(FileCount) do begin
    f := FileByIndex(i);
    if GetFileName(f) = name then begin
      Result := f;
      Exit;
    end;
  end;
end;

procedure WalkAndDumpPkids(elem: IInterface; depth: Integer);
var
  i: Integer;
  child, linked: IInterface;
  sig, nm, valStr, edidStr: string;
  fid: Cardinal;
begin
  if not Assigned(elem) then Exit;
  sig := Signature(elem);
  nm := Name(elem);
  if sig = 'PKID' then begin
    valStr := GetEditValue(elem);
    fid := GetNativeValue(elem);
    linked := LinksTo(elem);
    if Assigned(linked) then edidStr := EditorID(linked) else edidStr := '';
    if gPkidCount > 0 then gOut.Add(',');
    gOut.Add('            {');
    gOut.Add('              "raw_value": "' + Esc(valStr) + '",');
    gOut.Add('              "native_formid_hex": "' + IntToHex(fid, 8) + '",');
    gOut.Add('              "linked_edid": "' + Esc(edidStr) + '",');
    if Assigned(linked) then
      gOut.Add('              "linked_plugin": "' + Esc(GetFileName(GetFile(linked))) + '"')
    else
      gOut.Add('              "linked_plugin": null');
    gOut.Add('            }');
    Inc(gPkidCount);
    Exit;
  end;
  for i := 0 to Pred(ElementCount(elem)) do begin
    child := ElementByIndex(elem, i);
    WalkAndDumpPkids(child, depth + 1);
  end;
end;

procedure DumpPkidsForLink(rec: IInterface);
begin
  gOut.Add('          "pkids": [');
  gPkidCount := 0;
  WalkAndDumpPkids(rec, 0);
  gOut.Add('          ],');
  gOut.Add('          "pkid_count": ' + IntToStr(gPkidCount));
end;

procedure ProcessRecord(rec: IInterface);
var
  i, n: Integer;
  master, override: IInterface;
begin
  master := MasterOrSelf(rec);
  if not Assigned(master) then Exit;
  n := OverrideCount(master);
  gOut.Add('    {');
  gOut.Add('      "edid": "' + Esc(EditorID(master)) + '",');
  gOut.Add('      "signature": "' + Esc(Signature(master)) + '",');
  gOut.Add('      "lo_formid_hex": "' + IntToHex(GetLoadOrderFormID(master), 8) + '",');
  gOut.Add('      "chain_length": ' + IntToStr(n + 1) + ',');
  gOut.Add('      "chain": [');

  gOut.Add('        {');
  gOut.Add('          "plugin": "' + Esc(GetFileName(GetFile(master))) + '",');
  gOut.Add('          "is_master": true,');
  DumpPkidsForLink(master);
  if n = 0 then gOut.Add('        }') else gOut.Add('        },');

  for i := 0 to Pred(n) do begin
    override := OverrideByIndex(master, i);
    gOut.Add('        {');
    gOut.Add('          "plugin": "' + Esc(GetFileName(GetFile(override))) + '",');
    gOut.Add('          "is_master": false,');
    DumpPkidsForLink(override);
    if i = Pred(n) then gOut.Add('        }') else gOut.Add('        },');
  end;
  gOut.Add('      ]');
  gOut.Add('    }');
end;

function Initialize: Integer;
var
  target, edid, outPath: string;
  targetFile: IInterface;
  i, totalRecs: Integer;
  rec: IInterface;
begin
  target := GetArg('target');
  edid := GetArg('edid');
  outPath := GetArg('out');
  if (target = '') or (edid = '') or (outPath = '') then begin
    AddMessage('Usage: dump_npc_pkids_v2 --target=plugin --edid=ED --out=path');
    Result := 1; Exit;
  end;
  targetFile := FindFileByName(target);
  if not Assigned(targetFile) then begin
    AddMessage('ERROR: target plugin not loaded: ' + target);
    Result := 1; Exit;
  end;
  gOut := TStringList.Create;
  gOut.Add('{');
  gOut.Add('  "meta": { "tool": "dump_npc_pkids_v2", "tool_version": "' + TOOL_VERSION + '", "target": "' + Esc(target) + '", "edid": "' + Esc(edid) + '" },');
  gOut.Add('  "results": [');

  totalRecs := RecordCount(targetFile);
  for i := 0 to Pred(totalRecs) do begin
    rec := RecordByIndex(targetFile, i);
    if Signature(rec) = '' then Continue;
    if EditorID(rec) = edid then begin
      ProcessRecord(rec);
      Break;
    end;
  end;

  gOut.Add('  ]');
  gOut.Add('}');
  gOut.SaveToFile(outPath);
  AddMessage('Wrote: ' + outPath);
  gOut.Free;
  Result := 0;
end;

end.
