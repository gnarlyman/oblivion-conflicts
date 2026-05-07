{
  disable_all_patrols.pas — Override all OOO Imperial Legion mounted patrol
  ACHR/ACRE placements with the Initial Disable record-header flag (0x800).

  Targets:
    17 vanilla LegionRider* NPCs in Oblivion.esm
    19 LegionRider*B variants in Oscuro's_Oblivion_Overhaul.esm
    Plus their linked horse ACREs via XHRS.

  Output:
    Creates new ESP "Reborn - No Patrols.esp" with proper Cell/World GRUP
    nesting (handled by wbCopyElementToFile).

  Usage in xEdit:
    Tools menu -> Apply Script -> pick this file -> OK (no record selection
    needed; uses the Initialize-only entry point).
}
unit UserScript;

const
  TargetFileName = 'Reborn - No Patrols.esp';

  PatrolNpcLocals_Obl =
    '0700C0,0700C1,0700C2,0700C3,0700C4,0700C5,0700C6,0700C7,0700C8,0700C9,'
    + '0700CA,0700CB,0700CC,0700CD,18BA86,18BA88,18BA89';

  PatrolNpcLocals_OOOEsm =
    '004D3B,004D3F,0052B7,0052BE,0052C6,0052D1,0052D4,012391,03A27D,03A286,'
    + '03A28B,03A290,03A298,03A29F,03A78C,03A796,03AC9D,03B18A,03B194';


function HasFid(const list, fidStr: String): Boolean;
begin
  Result := Pos(fidStr, list) > 0;
end;


function GetNameLocalAndOwner(rec: IInterface; var ownerName: String; var nameLocal: Cardinal): Boolean;
var
  nameElement, linked, ownerFile: IInterface;
begin
  Result := False;
  nameElement := ElementByPath(rec, 'NAME');
  if not Assigned(nameElement) then Exit;
  linked := LinksTo(nameElement);
  if not Assigned(linked) then Exit;
  ownerFile := GetFile(linked);
  if not Assigned(ownerFile) then Exit;
  ownerName := GetFileName(ownerFile);
  nameLocal := FixedFormID(linked) and $FFFFFF;
  Result := True;
end;


procedure ProcessOneFile(srcFile, targetFile: IInterface; var achrCount, acreCount: Integer);
var
  i, n: Integer;
  rec, override, linked: IInterface;
  sig, ownerName: String;
  nameLocal, flags: Cardinal;
  shouldDisable: Boolean;
begin
  n := RecordCount(srcFile);
  for i := 0 to n - 1 do begin
    rec := RecordByIndex(srcFile, i);
    sig := Signature(rec);
    if sig <> 'ACHR' then Continue;
    shouldDisable := False;
    if GetNameLocalAndOwner(rec, ownerName, nameLocal) then begin
      if (ownerName = 'Oblivion.esm') and HasFid(PatrolNpcLocals_Obl, IntToHex(nameLocal, 6)) then
        shouldDisable := True;
      if (ownerName = 'Oscuro''s_Oblivion_Overhaul.esm') and HasFid(PatrolNpcLocals_OOOEsm, IntToHex(nameLocal, 6)) then
        shouldDisable := True;
    end;
    if not shouldDisable then Continue;

    override := wbCopyElementToFile(rec, targetFile, False, True);
    if Assigned(override) then begin
      flags := GetElementNativeValues(override, 'Record Header\Record Flags');
      SetElementNativeValues(override, 'Record Header\Record Flags', flags or $800);
      Inc(achrCount);
    end;

    linked := LinksTo(ElementByPath(rec, 'XHRS'));
    if Assigned(linked) and (Signature(linked) = 'ACRE') then begin
      override := wbCopyElementToFile(linked, targetFile, False, True);
      if Assigned(override) then begin
        flags := GetElementNativeValues(override, 'Record Header\Record Flags');
        SetElementNativeValues(override, 'Record Header\Record Flags', flags or $800);
        Inc(acreCount);
      end;
    end;
  end;
end;


function FindFileByName(const name: String): IInterface;
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
  obl, ooo, target: IInterface;
  achrCount, acreCount: Integer;
begin
  achrCount := 0;
  acreCount := 0;

  // Reuse target if it already exists, else create it
  target := FindFileByName(TargetFileName);
  if not Assigned(target) then
    target := AddNewFileName(TargetFileName, False);
  if not Assigned(target) then begin
    AddMessage('FAIL: could not create or find ' + TargetFileName);
    Result := 1;
    Exit;
  end;
  AddMessage('Target: ' + GetFileName(target));

  AddMasterIfMissing(target, 'Oblivion.esm');
  AddMasterIfMissing(target, 'Oscuro''s_Oblivion_Overhaul.esp');
  AddMasterIfMissing(target, 'Oscuro''s_Oblivion_Overhaul.esm');

  obl := FileByName('Oblivion.esm');
  if Assigned(obl) then ProcessOneFile(obl, target, achrCount, acreCount);

  ooo := FileByName('Oscuro''s_Oblivion_Overhaul.esp');
  if Assigned(ooo) then ProcessOneFile(ooo, target, achrCount, acreCount);

  AddMessage('Disabled ACHR=' + IntToStr(achrCount) + '  ACRE=' + IntToStr(acreCount));
  AddMessage('To save: close xEdit (or right-click target file -> Save).');

  Result := 0;
end;

end.
