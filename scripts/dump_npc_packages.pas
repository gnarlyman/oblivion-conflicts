{
  dump_npc_packages.pas - dump every PKID (AI Package reference)
  for an NPC across its full override chain in the loaded LO.

  Args:
    --target=plugin.esm    plugin to scan for the EDID (eg Oblivion.esm)
    --edid=editorid        NPC EDID
    --out=path             output JSON

  Output: per-link list of PKID entries with their resolved
  package EDID (or 'UNRESOLVED' / 'INJECTED').

  Multi-instance subrecord safe: enumerates every top-level
  child whose signature is PKID, instead of collapsing to one.
}
unit UserScript;

const
  TOOL_VERSION = '0.1.0';

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

procedure EmitOnePkid(child: IInterface; out_: TStringList; first: Boolean);
var
  linked: IInterface;
  valStr, edidStr, linkPlugin: string;
begin
  if not first then out_.Add(',');
  valStr := GetEditValue(child);
  edidStr := '';
  linkPlugin := '';
  try
    linked := LinksTo(child);
    if Assigned(linked) then begin
      edidStr := EditorID(linked);
      linkPlugin := GetFileName(GetFile(linked));
    end;
  except
    edidStr := '<EXCEPTION>';
  end;
  out_.Add('            {');
  out_.Add('              "raw_value": "' + Esc(valStr) + '",');
  out_.Add('              "linked_edid": "' + Esc(edidStr) + '",');
  if linkPlugin <> '' then
    out_.Add('              "linked_plugin": "' + Esc(linkPlugin) + '"')
  else
    out_.Add('              "linked_plugin": null');
  out_.Add('            }');
end;

procedure DumpPkidsForLink(rec: IInterface; out_: TStringList);
var
  i, j, count: Integer;
  child, grand: IInterface;
  sig: string;
begin
  out_.Add('          "pkids": [');
  count := 0;
  for i := 0 to Pred(ElementCount(rec)) do begin
    child := ElementByIndex(rec, i);
    sig := Signature(child);
    if sig <> 'PKID' then Continue;
    if ElementCount(child) > 0 then begin
      for j := 0 to Pred(ElementCount(child)) do begin
        grand := ElementByIndex(child, j);
        EmitOnePkid(grand, out_, count = 0);
        Inc(count);
      end;
    end else begin
      EmitOnePkid(child, out_, count = 0);
      Inc(count);
    end;
  end;
  out_.Add('          ],');
  out_.Add('          "pkid_count": ' + IntToStr(count));
end;

procedure ProcessRecord(rec: IInterface; out_: TStringList);
var
  i, n: Integer;
  master, override: IInterface;
begin
  master := MasterOrSelf(rec);
  if not Assigned(master) then Exit;
  n := OverrideCount(master);

  out_.Add('    {');
  out_.Add('      "edid": "' + Esc(EditorID(master)) + '",');
  out_.Add('      "signature": "' + Esc(Signature(master)) + '",');
  out_.Add('      "lo_formid_hex": "' + IntToHex(GetLoadOrderFormID(master), 8) + '",');
  out_.Add('      "chain_length": ' + IntToStr(n + 1) + ',');
  out_.Add('      "chain": [');

  out_.Add('        {');
  out_.Add('          "plugin": "' + Esc(GetFileName(GetFile(master))) + '",');
  out_.Add('          "is_master": true,');
  DumpPkidsForLink(master, out_);
  if n = 0 then out_.Add('        }') else out_.Add('        },');

  for i := 0 to Pred(n) do begin
    override := OverrideByIndex(master, i);
    out_.Add('        {');
    out_.Add('          "plugin": "' + Esc(GetFileName(GetFile(override))) + '",');
    out_.Add('          "is_master": false,');
    DumpPkidsForLink(override, out_);
    if i = Pred(n) then out_.Add('        }') else out_.Add('        },');
  end;
  out_.Add('      ]');
  out_.Add('    }');
end;

function Initialize: Integer;
var
  target, edid, outPath: string;
  targetFile: IInterface;
  out_: TStringList;
  i, totalRecs: Integer;
  rec: IInterface;
begin
  target := GetArg('target');
  edid := GetArg('edid');
  outPath := GetArg('out');
  if (target = '') or (edid = '') or (outPath = '') then begin
    AddMessage('Usage: dump_npc_packages --target=plugin --edid=ED --out=path');
    Result := 1; Exit;
  end;
  targetFile := FindFileByName(target);
  if not Assigned(targetFile) then begin
    AddMessage('ERROR: target plugin not loaded: ' + target);
    Result := 1; Exit;
  end;

  out_ := TStringList.Create;
  out_.Add('{');
  out_.Add('  "meta": { "tool": "dump_npc_packages", "tool_version": "' + TOOL_VERSION + '", "target": "' + Esc(target) + '", "edid": "' + Esc(edid) + '" },');
  out_.Add('  "results": [');

  totalRecs := RecordCount(targetFile);
  for i := 0 to Pred(totalRecs) do begin
    rec := RecordByIndex(targetFile, i);
    if Signature(rec) = '' then Continue;
    if EditorID(rec) = edid then begin
      ProcessRecord(rec, out_);
      Break;
    end;
  end;

  out_.Add('  ]');
  out_.Add('}');
  out_.SaveToFile(outPath);
  AddMessage('Wrote: ' + outPath);
  out_.Free;
  Result := 0;
end;

end.
