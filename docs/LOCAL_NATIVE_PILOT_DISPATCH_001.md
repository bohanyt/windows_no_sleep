# LOCAL NATIVE PILOT DISPATCH 001 — PROTECTED ENDPOINT COMPATIBILITY

Status: **AUTHORIZED — NON-MUTATING NATIVE PILOT ONLY**
Date: 2026-09-18
Repo: `bohanyt/windows_no_sleep`
Issue: #3
DRAFT PR: #4
Branch: `feat/v1-native-winforms`
Exact source head: `46d99c00c276266b5e53be31fa19eedebadc9990`

## Purpose

Validate whether the exact unsigned native C# pilot is accepted by a normal protected Windows endpoint before more V1 features are ported.

This is an EDR/runtime compatibility test only. It must not mutate Windows power policy, registry startup state, lid settings, sleep timeouts, battery settings, hibernation, or update services.

## Exact artifact

GitHub Actions run: `35203872675`
Artifact ID: `10489380366`
Artifact name: `WindowsNoSleep-native-pilot`

Expected SHA-256:
- distributable nested ZIP: `758DBF9A68A8CA830332FEEBE7A57722CFA69EB512957590F1AA81627F731B87`
- `WindowsNoSleep.exe`: `4EC31D00B718A541021773590423A9385895FBA812964F3912C2983C55F2FB51`

Signing status: **UNSIGNED PILOT**.

## Required context

- normal non-elevated Windows user;
- antivirus/EDR/Defender remains enabled normally;
- no exclusions, allowlists, quarantine release, execution-policy bypass, or security disabling;
- no admin elevation;
- no lid-close, battery unplug, sleep/hibernate/restart/shutdown test;
- no source edits, commits, or power-policy changes.

Prefer a spare/test laptop over the previously affected endpoint.

## Steps

1. Download/extract the exact CI artifact.
2. If the downloaded Actions artifact contains the distributable ZIP, extract that inner ZIP once.
3. Verify the EXE hash:
   `Get-FileHash .\WindowsNoSleep.exe -Algorithm SHA256`
4. STOP if the EXE hash differs from the expected value above.
5. Double-click `WindowsNoSleep.exe`.
6. Observe:
   - no console window;
   - tray icon appears;
   - status is Protected;
   - left-click/open Settings works.
7. In the app:
   - click Stop Protection and confirm Stopped;
   - click Start Protection and confirm Protected;
   - click Exit and confirm the tray icon disappears.
8. Observe endpoint security during and immediately after the run.

## Pass

PASS only if:
- exact EXE hash matched;
- app launched normally;
- Protected -> Stopped -> Protected worked;
- Exit worked;
- no AV/EDR/security warning, block, quarantine, deletion, or remediation occurred;
- no admin/exclusion/security bypass was used.

Evidence label on PASS: `NATIVE_PILOT_PROTECTED_ENDPOINT_ACCEPTED`.

This is NOT yet `EDR_VERIFIED` for the final product because the pilot does not contain recovery/policy-write features.

## Stop conditions

If security software warns, blocks, quarantines, removes files, or terminates the app:
- STOP immediately;
- do not rerun;
- do not rename/rebuild/pack the EXE;
- do not add an exclusion or allowlist;
- preserve screenshots/alert classification/path/hash where allowed;
- report the result to Control Tower.

Also STOP on any unexpected elevation prompt, crash, or abnormal Windows-setting change.

## Evidence to return

- Windows version/build;
- endpoint-security product if visible;
- EXE SHA-256;
- whether tray appeared;
- Protected/Stopped/Protected results;
- Exit result;
- any warning/quarantine/block screenshot or exact text;
- whether the EXE still exists afterward;
- whether any unexpected prompt occurred.

End with:

`CONTROL_TOWER_READY`
