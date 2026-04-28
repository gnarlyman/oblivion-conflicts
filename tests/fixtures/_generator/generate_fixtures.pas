{
  generate_fixtures.pas — builds Master.esm + OverrideA.esp + OverrideB.esp
  for the oblivion-conflicts test suite.

  Run from xEdit GUI:
    1. Launch TES4Edit with NO modules selected (cancel the load dialog by
       pressing OK on an empty selection — xEdit will start with no plugins).
    2. From the menu: Other > Run script... and select this file.
    3. The script creates all three plugins. xEdit prompts to save them on exit.
    4. Move the resulting files from xEdit's data dir into
       tests/fixtures/data/ in this repo.
}
unit UserScript;

var
  fMaster, fOverrideA, fOverrideB: IInterface;

function AddRecord(plugin: IInterface; sig: string; formIDLocal: cardinal; edid: string): IInterface;
var
  grp, rec: IInterface;
begin
  grp := Add(plugin, sig, True);
  rec := Add(grp, sig, True);
  SetLoadOrderFormID(rec, GetLoadOrder(plugin) * $01000000 + formIDLocal);
  SetElementEditValues(rec, 'EDID', edid);
  Result := rec;
end;

procedure BuildMaster;
var
  weap, armo, cont, dlted, items, item: IInterface;
begin
  fMaster := AddNewFileName('Master.esm', True);  // True = ESM flag (older API); ignored in newer xEdit if signature changed

  // WEAP: shared by all three plugins
  weap := AddRecord(fMaster, 'WEAP', $001001, 'TestSword');
  SetElementEditValues(weap, 'FULL', 'Test Sword');
  SetElementEditValues(weap, 'MODL\MODL', 'Weapons\TestSword.NIF');
  SetElementEditValues(weap, 'DATA\Type', 'Blade One Hand');
  SetElementEditValues(weap, 'DATA\Speed', '1.0');
  SetElementEditValues(weap, 'DATA\Reach', '1.0');
  SetElementEditValues(weap, 'DATA\Value', '10');
  SetElementEditValues(weap, 'DATA\Health', '100');
  SetElementEditValues(weap, 'DATA\Weight', '5.0');
  SetElementEditValues(weap, 'DATA\Damage', '5');

  // ARMO: shared by Master and OverrideA only
  armo := AddRecord(fMaster, 'ARMO', $001002, 'TestArmor');
  SetElementEditValues(armo, 'FULL', 'Test Armor');
  SetElementEditValues(armo, 'DATA\Value', '50');
  SetElementEditValues(armo, 'DATA\Health', '200');
  SetElementEditValues(armo, 'DATA\Weight', '10.0');
  SetElementEditValues(armo, 'DATA\Armor', '15');

  // CONT: master version with 1 inventory entry; OverrideB will add another.
  // In TES4 the items array is named 'Items' (not 'CNTO'); each item exposes
  // 'Item' (FormID) and 'Count' (int) directly. See xEdit's bundled
  // 'Add into container.pas' for the canonical pattern.
  cont := AddRecord(fMaster, 'CONT', $001003, 'TestChest');
  SetElementEditValues(cont, 'FULL', 'Test Chest');
  items := Add(cont, 'Items', True);
  item := ElementByIndex(items, 0);
  SetElementNativeValues(item, 'Item', $00001001);
  SetElementNativeValues(item, 'Count', 1);

  // DLTED: a record OverrideA will mark deleted
  dlted := AddRecord(fMaster, 'WEAP', $001004, 'TestDagger');
  SetElementEditValues(dlted, 'FULL', 'Test Dagger');
end;

procedure BuildOverrideA;
var
  weapM, weapO, armoM, armoO, dltedM, dltedO: IInterface;
  masterIdx: cardinal;
begin
  fOverrideA := AddNewFileName('OverrideA.esp', False);
  AddMasterIfMissing(fOverrideA, 'Master.esm');
  masterIdx := GetLoadOrder(fMaster) * $01000000;

  // Override the WEAP with different stats
  weapM := RecordByFormID(fMaster, $001001 + masterIdx, False);
  weapO := wbCopyElementToFile(weapM, fOverrideA, False, True);
  SetElementEditValues(weapO, 'DATA\Damage', '7');
  SetElementEditValues(weapO, 'DATA\Value', '15');

  // Override ARMO with different value
  armoM := RecordByFormID(fMaster, $001002 + masterIdx, False);
  armoO := wbCopyElementToFile(armoM, fOverrideA, False, True);
  SetElementEditValues(armoO, 'DATA\Armor', '20');

  // Mark TestDagger deleted
  dltedM := RecordByFormID(fMaster, $001004 + masterIdx, False);
  dltedO := wbCopyElementToFile(dltedM, fOverrideA, False, True);
  SetIsDeleted(dltedO, True);
end;

procedure BuildOverrideB;
var
  weapM, weapO, contM, contO, items, item: IInterface;
  masterIdx: cardinal;
begin
  fOverrideB := AddNewFileName('OverrideB.esp', False);
  AddMasterIfMissing(fOverrideB, 'Master.esm');
  masterIdx := GetLoadOrder(fMaster) * $01000000;

  // Override the same WEAP as A, but different fields → 3-way conflict
  weapM := RecordByFormID(fMaster, $001001 + masterIdx, False);
  weapO := wbCopyElementToFile(weapM, fOverrideB, False, True);
  SetElementEditValues(weapO, 'DATA\Damage', '6');
  SetElementEditValues(weapO, 'DATA\Speed', '1.2');

  // Add a CNTO entry to TestChest (repeating subrecord case).
  // The Items array already has the inherited entry from Master; append a new one.
  contM := RecordByFormID(fMaster, $001003 + masterIdx, False);
  contO := wbCopyElementToFile(contM, fOverrideB, False, True);
  items := ElementByName(contO, 'Items');
  item := ElementAssign(items, HighInteger, nil, False);
  SetElementNativeValues(item, 'Item', $00001002);
  SetElementNativeValues(item, 'Count', 2);
end;

function Initialize: integer;
begin
  BuildMaster;
  BuildOverrideA;
  BuildOverrideB;
  AddMessage('Done. Save the three new plugins via File > Save when prompted.');
  Result := 0;
end;

end.
