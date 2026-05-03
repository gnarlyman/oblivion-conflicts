{
  add_bash_tag.pas - append a Bash tag to a plugin's TES4 description.
  Wrye Bash reads {{BASH:tag1,tag2,...}} markers in the description.

  Args:
    --target=plugin.esp   plugin to modify
    --tag=TagName         tag to add (e.g. NoMerge)

  Idempotent: skips if tag already present.
}
unit UserScript;

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

function Initialize: Integer;
var
  target, tag, desc, newDesc: string;
  f, hdr, snam: IInterface;
  bashStart, bashEnd, openBrace, closeBrace: Integer;
  existingTags, before, after: string;
begin
  target := GetArg('target');
  tag := GetArg('tag');
  if (target = '') or (tag = '') then begin
    AddMessage('Usage: add_bash_tag --target=plugin.esp --tag=TagName');
    Result := 1; Exit;
  end;
  f := FindFileByName(target);
  if not Assigned(f) then begin
    AddMessage('ERROR: target plugin not loaded: ' + target);
    Result := 1; Exit;
  end;
  hdr := ElementByIndex(f, 0);
  snam := ElementByPath(hdr, 'SNAM');
  if not Assigned(snam) then begin
    AddMessage('Plugin has no SNAM (description); adding one with the tag.');
    Add(hdr, 'SNAM', True);
    snam := ElementByPath(hdr, 'SNAM');
    SetEditValue(snam, '{{BASH:' + tag + '}}');
  end else begin
    desc := GetEditValue(snam);
    AddMessage('Existing description: ' + desc);
    bashStart := Pos('{{BASH:', desc);
    if bashStart = 0 then begin
      newDesc := desc + ' {{BASH:' + tag + '}}';
      SetEditValue(snam, newDesc);
      AddMessage('Added new BASH marker; new description: ' + newDesc);
    end else begin
      // Find the matching }} after {{BASH:
      bashEnd := Pos('}}', Copy(desc, bashStart, MaxInt));
      if bashEnd = 0 then begin
        AddMessage('Malformed BASH marker (no closing braces); aborting');
        Result := 1; Exit;
      end;
      bashEnd := bashStart + bashEnd - 1;
      existingTags := Copy(desc, bashStart + 7, bashEnd - bashStart - 7);
      AddMessage('Existing BASH tags: ' + existingTags);
      // Idempotency check: look for ',TagName' or 'TagName,' or exact 'TagName'
      if (Pos(',' + tag + ',', ',' + existingTags + ',') > 0) then begin
        AddMessage('Tag already present; nothing to do');
        Result := 0; Exit;
      end;
      before := Copy(desc, 1, bashStart - 1);
      after  := Copy(desc, bashEnd + 2, MaxInt);
      newDesc := before + '{{BASH:' + existingTags + ',' + tag + '}}' + after;
      SetEditValue(snam, newDesc);
      AddMessage('Updated description: ' + newDesc);
    end;
  end;
  Result := 0;
end;

end.
