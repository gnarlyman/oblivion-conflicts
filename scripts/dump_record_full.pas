{
  dump_record_full.pas - locate records by EDID inside --target plugin
  and dump EVERY subrecord across every link in the override chain.

  Unlike dump_chain_subrecord (which dumps one subrecord across the chain),
  this dumps ALL top-level subrecords for the record at every chain link,
  flagging which ones differ from the master. Designed for "what did this
  patch actually change" investigations.

  Args:
    --target=plugin.esp       required (the plugin we walk to find records)
    --edid=editorid           required (one or more)
    --out=path                required

  Output: JSON envelope identical in shape to other oblivion-conflicts
  queries. results[] entries carry:
    target_lo_formid_hex      the master record's LO-form FID
    edid, signature
    chain[]                   one entry per override link, each with:
      plugin                  filename
      subrecords[]            every top-level subrecord at this link
        sig                   4-char signature (or element name)
        value                 GetEditValue (truncated at 4096 chars)
        differs_from_master   true if value differs from master's value
                              for this same sig

  IMPORTANT: do not place curly braces of any kind inside this block
  comment - JvInterpreter ends the comment at the first close-brace and
  the leftover text reaches the parser as code.
}
unit UserScript;

const
  TOOL_VERSION = '0.1.0';
  MAX_VALUE_LEN = 4096;

function Esc(const s: string): string;
begin
  Result := StringReplace(s, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
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

function GetArgs(const key: string): TStringList;
var
  i: Integer;
  prefix, s: string;
begin
  Result := TStringList.Create;
  prefix := '--' + key + '=';
  for i := 0 to ParamCount do begin
    s := ParamStr(i);
    if Copy(s, 1, Length(prefix)) = prefix then
      Result.Add(Copy(s, Length(prefix) + 1, MaxInt));
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

function SubElementName(elem: IInterface): string;
var
  sig: string;
begin
  sig := Signature(elem);
  if sig <> '' then
    Result := sig
  else
    Result := Name(elem);
end;

function SafeEditValue(elem: IInterface): string;
begin
  Result := '';
  try
    Result := GetEditValue(elem);
  except
    Result := '<EXCEPTION>';
  end;
  if Length(Result) > MAX_VALUE_LEN then
    Result := Copy(Result, 1, MAX_VALUE_LEN) + '...<truncated>';
end;

function FindSubByName(rec: IInterface; const targetName: string): IInterface;
var
  i, j, slashPos, colonPos, idx: Integer;
  child, grand: IInterface;
  parentName, indexAndName, indexStr, grandName: string;
begin
  Result := nil;
  // Path notation: "PARENT/INDEX:CHILD" or just "TOP_LEVEL_SIG"
  slashPos := Pos('/', targetName);
  if slashPos = 0 then begin
    // Top-level lookup
    for i := 0 to Pred(ElementCount(rec)) do begin
      child := ElementByIndex(rec, i);
      if SubElementName(child) = targetName then begin
        Result := child;
        Exit;
      end;
    end;
    Exit;
  end;
  // Nested lookup: find parent, then child by index
  parentName := Copy(targetName, 1, slashPos - 1);
  indexAndName := Copy(targetName, slashPos + 1, MaxInt);
  colonPos := Pos(':', indexAndName);
  if colonPos = 0 then Exit;
  indexStr := Copy(indexAndName, 1, colonPos - 1);
  grandName := Copy(indexAndName, colonPos + 1, MaxInt);
  idx := StrToIntDef(indexStr, -1);
  if idx < 0 then Exit;
  for i := 0 to Pred(ElementCount(rec)) do begin
    child := ElementByIndex(rec, i);
    if SubElementName(child) = parentName then begin
      if idx < ElementCount(child) then begin
        grand := ElementByIndex(child, idx);
        if SubElementName(grand) = grandName then begin
          Result := grand;
          Exit;
        end;
      end;
      Exit;
    end;
  end;
end;

// Collect names of top-level subrecords AND one level of struct/array children.
// Children are recorded as "PARENT/CHILD" so the same name can appear under
// different parents.
function CollectSubNames(rec: IInterface; outList: TStringList): Integer;
var
  i, j: Integer;
  child, grand: IInterface;
  nm, gnm: string;
begin
  Result := 0;
  for i := 0 to Pred(ElementCount(rec)) do begin
    child := ElementByIndex(rec, i);
    nm := SubElementName(child);
    if outList.IndexOf(nm) < 0 then begin
      outList.Add(nm);
      Inc(Result);
    end;
    // Recurse one level for arrays/structs (Stages, Effects, Targets, etc.)
    if (DefType(child) = dtArray) or (DefType(child) = dtStruct) then begin
      for j := 0 to Pred(ElementCount(child)) do begin
        grand := ElementByIndex(child, j);
        gnm := nm + '/' + IntToStr(j) + ':' + SubElementName(grand);
        if outList.IndexOf(gnm) < 0 then begin
          outList.Add(gnm);
          Inc(Result);
        end;
      end;
    end;
  end;
end;

procedure DumpChainLink(rec: IInterface; allSubNames: TStringList;
                        masterValues: TStringList; out_: TStringList;
                        firstLink: Boolean);
var
  i: Integer;
  nm, val, masterVal: string;
  child: IInterface;
  differs: Boolean;
  comma: string;
begin
  out_.Add('        "subrecords": [');
  for i := 0 to Pred(allSubNames.Count) do begin
    nm := allSubNames[i];
    child := FindSubByName(rec, nm);
    if Assigned(child) then begin
      val := SafeEditValue(child);
    end else begin
      val := '';
    end;
    if firstLink then begin
      masterVal := val;
      masterValues.Add(nm + '=' + val);
      differs := False;
    end else begin
      masterVal := masterValues.Values[nm];
      differs := (val <> masterVal);
    end;
    if i < Pred(allSubNames.Count) then comma := ',' else comma := '';
    out_.Add('          {');
    out_.Add('            "sig": "' + Esc(nm) + '",');
    if Assigned(child) then begin
      out_.Add('            "present": true,');
      out_.Add('            "value": "' + Esc(val) + '",');
    end else begin
      out_.Add('            "present": false,');
      out_.Add('            "value": null,');
    end;
    if differs then
      out_.Add('            "differs_from_master": true')
    else
      out_.Add('            "differs_from_master": false');
    out_.Add('          }' + comma);
  end;
  out_.Add('        ]');
end;

procedure ProcessRecord(rec: IInterface; edid: string; out_: TStringList;
                        firstResult: Boolean);
var
  i: Integer;
  master: IInterface;
  override: IInterface;
  numOverrides: Integer;
  allSubNames: TStringList;
  masterValues: TStringList;
  comma: string;
begin
  master := MasterOrSelf(rec);
  if not Assigned(master) then Exit;

  allSubNames := TStringList.Create;
  masterValues := TStringList.Create;
  try
    // Collect subrecord names present in any chain link
    CollectSubNames(master, allSubNames);
    numOverrides := OverrideCount(master);
    for i := 0 to Pred(numOverrides) do begin
      override := OverrideByIndex(master, i);
      CollectSubNames(override, allSubNames);
    end;

    if not firstResult then out_.Add('    ,{') else out_.Add('    {');
    out_.Add('      "edid": "' + Esc(edid) + '",');
    out_.Add('      "signature": "' + Esc(Signature(master)) + '",');
    out_.Add('      "target_lo_formid_hex": "' + IntToHex(GetLoadOrderFormID(master), 8) + '",');
    out_.Add('      "name": "' + Esc(Name(master)) + '",');
    out_.Add('      "chain": [');

    // Master link
    out_.Add('        {');
    out_.Add('          "plugin": "' + Esc(GetFileName(GetFile(master))) + '",');
    out_.Add('          "is_master": true,');
    DumpChainLink(master, allSubNames, masterValues, out_, True);
    if numOverrides = 0 then out_.Add('        }') else out_.Add('        },');

    // Each override
    for i := 0 to Pred(numOverrides) do begin
      override := OverrideByIndex(master, i);
      out_.Add('        {');
      out_.Add('          "plugin": "' + Esc(GetFileName(GetFile(override))) + '",');
      out_.Add('          "is_master": false,');
      DumpChainLink(override, allSubNames, masterValues, out_, False);
      if i = Pred(numOverrides) then out_.Add('        }') else out_.Add('        },');
    end;

    out_.Add('      ]');
    out_.Add('    }');
  finally
    allSubNames.Free;
    masterValues.Free;
  end;
end;

function Initialize: Integer;
var
  target, outPath: string;
  edids: TStringList;
  targetFile: IInterface;
  out_: TStringList;
  i, j, totalRecs: Integer;
  rec: IInterface;
  recEdid: string;
  matched: TStringList;
  firstResult: Boolean;
  startTime: TDateTime;
  durationMs: Integer;
begin
  startTime := Now;
  target := GetArg('target');
  outPath := GetArg('out');
  edids := GetArgs('edid');

  if (target = '') or (outPath = '') or (edids.Count = 0) then begin
    AddMessage('Usage: dump_record_full --target=plugin.esp --edid=ED1 [--edid=ED2 ...] --out=path');
    edids.Free;
    Result := 1;
    Exit;
  end;

  targetFile := FindFileByName(target);
  if not Assigned(targetFile) then begin
    AddMessage('ERROR: target plugin not loaded: ' + target);
    edids.Free;
    Result := 1;
    Exit;
  end;

  AddMessage('Searching ' + target + ' for ' + IntToStr(edids.Count) + ' EDIDs...');

  out_ := TStringList.Create;
  matched := TStringList.Create;
  firstResult := True;

  out_.Add('{');
  out_.Add('  "meta": {');
  out_.Add('    "tool": "dump_record_full",');
  out_.Add('    "tool_version": "' + TOOL_VERSION + '",');
  out_.Add('    "target": "' + Esc(target) + '",');
  out_.Add('    "edids_requested": ' + IntToStr(edids.Count));
  out_.Add('  },');
  out_.Add('  "results": [');

  totalRecs := RecordCount(targetFile);
  for i := 0 to Pred(totalRecs) do begin
    rec := RecordByIndex(targetFile, i);
    if Signature(rec) = '' then Continue;
    recEdid := EditorID(rec);
    for j := 0 to Pred(edids.Count) do begin
      if recEdid = edids[j] then begin
        ProcessRecord(rec, recEdid, out_, firstResult);
        firstResult := False;
        matched.Add(recEdid);
        Break;
      end;
    end;
  end;

  out_.Add('  ]');
  out_.Add('}');

  out_.SaveToFile(outPath);

  durationMs := Round((Now - startTime) * 86400000);
  AddMessage('Matched ' + IntToStr(matched.Count) + ' of ' + IntToStr(edids.Count) + ' EDIDs');
  AddMessage('Wrote: ' + outPath);
  AddMessage('Duration: ' + IntToStr(durationMs) + 'ms');

  edids.Free;
  out_.Free;
  matched.Free;
  Result := 0;
end;

end.
