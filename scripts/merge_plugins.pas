{
  merge_plugins.pas - copy every record from one or more source plugins
  into a target plugin (creating if needed) via wbCopyElementToFile.
  Optionally replace the SCTX of one named SCPT record with file content.

  Args:
    --source=plugin.esp       repeatable. Sources are processed in order;
                              later sources override earlier ones for
                              records with the same FormID.
    --target=plugin.esp       required. Created via AddNewFileName if it
                              doesn't already exist in the load order.
    --sctx-edid=EDID          optional. After merging, find this SCPT
                              and replace its SCTX with the file below.
    --sctx-file=path          optional. Required if --sctx-edid set.

  IMPORTANT: do not place curly braces inside this block comment.
}
unit UserScript;

const
  TOOL_VERSION = '0.1.0';

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
    if SameText(GetFileName(f), name) then begin
      Result := f;
      Exit;
    end;
  end;
end;

procedure CopyAllRecords(src, target: IInterface; var copied: Integer; var skipped: Integer);
var
  i, j: Integer;
  group, rec, dst: IInterface;
  sig, recSig, edid, errMsg: string;
  loggedSkipKinds: TStringList;
begin
  loggedSkipKinds := TStringList.Create;
  try
    // Iterate top-level groups, then records inside.
    for i := 0 to Pred(ElementCount(src)) do begin
      group := ElementByIndex(src, i);
      sig := Signature(group);
      if sig = 'TES4' then Continue;  // skip header
      // Group element — iterate records
      for j := 0 to Pred(ElementCount(group)) do begin
        rec := ElementByIndex(group, j);
        recSig := Signature(rec);
        if recSig = '' then Continue;
        edid := EditorID(rec);
        try
          dst := wbCopyElementToFile(rec, target, False, True);
          if Assigned(dst) then begin
            Inc(copied);
          end else begin
            Inc(skipped);
            if loggedSkipKinds.IndexOf(recSig + ':nil') < 0 then begin
              AddMessage('  first nil-result for sig=' + recSig + ' edid=' + edid);
              loggedSkipKinds.Add(recSig + ':nil');
            end;
          end;
        except
          on E: Exception do begin
            Inc(skipped);
            errMsg := E.Message;
            if loggedSkipKinds.IndexOf(recSig + ':' + errMsg) < 0 then begin
              AddMessage('  first exc sig=' + recSig + ' edid=' + edid + ' msg=' + errMsg);
              loggedSkipKinds.Add(recSig + ':' + errMsg);
            end;
          end;
        end;
      end;
    end;
  finally
    loggedSkipKinds.Free;
  end;
end;

procedure AddSourceMasters(src, target: IInterface);
var
  hdr, mastersGroup, masterRec: IInterface;
  i: Integer;
  mname: string;
begin
  hdr := ElementByIndex(src, 0);
  if not Assigned(hdr) then Exit;
  mastersGroup := ElementByPath(hdr, 'Master Files');
  if not Assigned(mastersGroup) then Exit;
  for i := 0 to Pred(ElementCount(mastersGroup)) do begin
    masterRec := ElementByIndex(mastersGroup, i);
    mname := GetEditValue(ElementByPath(masterRec, 'MAST'));
    if mname <> '' then AddMasterIfMissing(target, mname);
  end;
end;

function FindRecordByEDIDInTarget(target: IInterface; const edid: string): IInterface;
var
  i, j: Integer;
  group, rec: IInterface;
begin
  Result := nil;
  for i := 0 to Pred(ElementCount(target)) do begin
    group := ElementByIndex(target, i);
    if Signature(group) = 'TES4' then Continue;
    for j := 0 to Pred(ElementCount(group)) do begin
      rec := ElementByIndex(group, j);
      if SameText(EditorID(rec), edid) then begin
        Result := rec;
        Exit;
      end;
    end;
  end;
end;

function Initialize: Integer;
var
  sources: TStringList;
  targetName, sctxEdid, sctxFile: string;
  target, src, rec, sctxElem: IInterface;
  i, totalCopied, totalSkipped, srcCopied, srcSkipped: Integer;
  sl: TStringList;
  newSCTX: string;
begin
  sources := GetArgs('source');
  targetName := GetArg('target');
  sctxEdid := GetArg('sctx-edid');
  sctxFile := GetArg('sctx-file');

  if (sources.Count = 0) or (targetName = '') then begin
    AddMessage('Usage: merge_plugins --source=A.esp --source=B.esp --target=C.esp [--sctx-edid=ID --sctx-file=path]');
    Result := 1; Exit;
  end;

  AddMessage('merge_plugins v' + TOOL_VERSION);
  AddMessage('Target: ' + targetName);
  AddMessage('Sources (' + IntToStr(sources.Count) + '):');
  for i := 0 to Pred(sources.Count) do
    AddMessage('  ' + sources[i]);

  // Resolve or create target
  target := FindFileByName(targetName);
  if not Assigned(target) then begin
    AddMessage('Target not loaded; creating new file');
    target := AddNewFileName(targetName);
    if not Assigned(target) then begin
      AddMessage('ERROR: AddNewFileName returned nil');
      Result := 2; Exit;
    end;
  end;

  // Pre-add Oblivion.esm so wbCopyElementToFile can map any 0x00xxxxxx
  // FormID to a local FileID. Without this, copies fail with "Load order
  // FileID [00] can not be mapped".
  AddMasterIfMissing(target, 'Oblivion.esm');

  totalCopied := 0;
  totalSkipped := 0;
  for i := 0 to Pred(sources.Count) do begin
    src := FindFileByName(sources[i]);
    if not Assigned(src) then begin
      AddMessage('WARN: source not loaded: ' + sources[i]);
      Continue;
    end;
    // Pre-add the source's masters AND the source itself (so injected
    // records and override-of-source-record references resolve).
    AddSourceMasters(src, target);
    AddMasterIfMissing(target, sources[i]);

    AddMessage('Copying records from ' + sources[i] + '...');
    srcCopied := 0;
    srcSkipped := 0;
    CopyAllRecords(src, target, srcCopied, srcSkipped);
    AddMessage('  copied=' + IntToStr(srcCopied) + ' skipped=' + IntToStr(srcSkipped));
    totalCopied := totalCopied + srcCopied;
    totalSkipped := totalSkipped + srcSkipped;
  end;
  AddMessage('Total copied=' + IntToStr(totalCopied) + ' skipped=' + IntToStr(totalSkipped));

  // Apply SCTX patch if requested
  if (sctxEdid <> '') and (sctxFile <> '') then begin
    rec := FindRecordByEDIDInTarget(target, sctxEdid);
    if not Assigned(rec) then begin
      AddMessage('ERROR: SCTX-target EDID not found in target after merge: ' + sctxEdid);
      Result := 4; Exit;
    end;
    sctxElem := ElementByPath(rec, 'SCTX');
    if not Assigned(sctxElem) then begin
      AddMessage('ERROR: target record has no SCTX element');
      Result := 5; Exit;
    end;
    sl := TStringList.Create;
    try
      sl.LoadFromFile(sctxFile);
      newSCTX := sl.Text;
    finally
      sl.Free;
    end;
    SetEditValue(sctxElem, newSCTX);
    AddMessage('SCTX patched on ' + sctxEdid + ' (' + IntToStr(Length(newSCTX)) + ' chars)');
  end;

  AddMessage('OK');
  sources.Free;
  Result := 0;
end;

end.
