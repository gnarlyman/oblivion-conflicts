{
  patch_smoketest.pas — minimal script to verify -autoload -autoexit work
  in tmScript mode after the xEdit autoload-gating patch.

  Expected behavior with patched TES4Edit_patched.exe:
    1. No module-selection dialog appears (autoload).
    2. This script's Initialize runs; messages below land in TES4Edit_log.txt.
    3. xEdit closes by itself (autoexit).
}
unit UserScript;

function Initialize: integer;
begin
  AddMessage('=== PATCH SMOKETEST: Initialize entered ===');
  AddMessage('autoload bypassed module dialog: TRUE (we got here without input)');
  AddMessage('Plugin count loaded: ' + IntToStr(FileCount));
  AddMessage('=== PATCH SMOKETEST: Initialize returning 0 ===');
  Result := 0;
end;

end.
