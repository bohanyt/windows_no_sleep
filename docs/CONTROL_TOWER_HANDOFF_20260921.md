# Windows No Sleep — Control Tower Successor Handoff

Status: **ACTIVE SUCCESSOR HANDOFF**
Date: 2026-09-21
Repository: `bohanyt/windows_no_sleep`
Owner: Bohan / `bohanyt`
Role handed off: one continuing Control Tower for the Windows No Sleep project

## 1. Successor operating rule

GitHub is the source of truth. Old chat history is context only.

Before making any substantive decision, fresh-read in this order:

1. `README.md`
2. `docs/PLAN_V1.md`
3. `docs/TEST_PLAN.md`
4. `docs/CONTROL_TOWER.md`
5. `docs/NATIVE_RUNTIME_DECISION.md`
6. `PROGRESS.md`
7. latest comments on Issue #1
8. latest comments on Issue #3
9. DRAFT PR #4 metadata/head/CI
10. `docs/LOCAL_NATIVE_PILOT_DISPATCH_001.md`

Do not trust the SHAs in this handoff if GitHub has moved. They are orientation only; always fresh-check.

The project stays small: one Control Tower, one implementation lane, one local Windows executor only when physical evidence is needed. Do not create a swarm or competing rewrite branch.

## 2. Current product goal

Build a small portable Windows utility that keeps the **computer/workloads running**, while allowing the display to dim/off.

Target operator experience remains:

`double-click -> Protection starts immediately -> tray icon -> click tray for Settings`

Primary platform: Windows 11, including Modern Standby laptops and headless/display-off desktop/NUC use.

Safety remains higher priority than staying awake:
- Battery Safety base threshold 15%;
- do not disable Windows critical-battery behavior;
- do not globally disable hibernation;
- do not sabotage Windows Update/Medic/BITS;
- do not change power-button behavior;
- no security bypass/EDR evasion.

## 3. Why the architecture changed

The original PowerShell-first V1 prototype reached useful functional evidence but then Issue #3 reported endpoint-security quarantine involving the PowerShell runtime/source and the `WindowsNoSleepRecovery` RunOnce recovery path.

Root cause attribution to one exact heuristic remains unproven. Do NOT state that RunOnce, PowerShell, or unsigned code individually caused the detection.

Control Tower correctly stopped the old physical Dispatch 004 rather than rerunning or bypassing security.

The owner then approved the native replacement direction in:

`docs/NATIVE_RUNTIME_DECISION.md`

The old PowerShell implementation is retained for historical/reference evidence only.

## 4. Active and superseded lanes

### Active implementation lane

Branch:
`feat/v1-native-winforms`

DRAFT PR:
`#4 — Native WinForms V1 pilot — compiled, non-mutating packaging lane`

Orientation head as of this handoff:
`46d99c00c276266b5e53be31fa19eedebadc9990`

Do not assume that SHA is still current; fresh-check PR #4.

### Superseded implementation lane

Branch:
`feat/v1-portable-tray`

Old DRAFT PR #2 is closed and superseded/reference-only.

Do not reopen it as a competing implementation lane.

Old PowerShell local Dispatch 004 is cancelled/HOLD and must not be run.

## 5. Approved native architecture

Current approved direction:

- C# WinForms;
- .NET Framework 4.8;
- portable x64 `WindowsNoSleep.exe`;
- normal non-elevated `asInvoker` manifest;
- no PowerShell/CMD/script-host child process in normal operation;
- no embedded/extracted script payload;
- no obfuscation/packer/runtime download;
- no automatic elevation;
- no AV/EDR bypass or broad exclusions;
- no signing purchase required for the first pilot.

The first pilot is deliberately unsigned.

## 6. Approved recovery direction for the later mutating build

The old hidden PowerShell + RunOnce `-RecoveryOnly` mechanism is retired.

Approved layered native recovery direction:

1. durable versioned recovery journal written before any temporary power-policy mutation;
2. Windows Application Recovery and Restart:
   - `RegisterApplicationRecoveryCallback`
   - `RegisterApplicationRestart`
3. restore-before-protect on every normal app launch when a pending journal exists.

ARR is best-effort only. It is not a guarantee for force-kill, EDR termination, power loss, kernel crash, or firmware failure.

Current native V1 direction does NOT include:
- RunOnce recovery;
- scheduled-task recovery;
- Windows service;
- hidden respawn helper.

If a safe recovery route is not available for a requested policy mutation, that capability must fail closed.

## 7. Native Stage B pilot already implemented

At the orientation head above, the pilot implements only:

- ordinary WinForms tray application;
- direct `PowerCreateRequest` / `PowerSetRequest(PowerRequestSystemRequired)`;
- protection starts immediately;
- tray icon;
- small status/settings UI;
- Stop Protection;
- Start Protection;
- Exit cleanup;
- `--self-test` that acquires/releases only the SystemRequired request;
- x64 Release build;
- CI artifact + hashes.

The pilot intentionally does NOT implement yet:

- lid-action writes;
- AC/DC sleep-timeout writes;
- recovery journal;
- ARR;
- registry startup persistence;
- RunOnce;
- Battery Safety controller;
- shutdown/restart guard;
- installer;
- signing.

Therefore this pilot should be safe to use as a packaging/EDR compatibility gate without persistent Windows power-policy mutation.

## 8. Hosted evidence already obtained

Hosted GitHub Actions run:

`35203872675`

At exact source head:

`46d99c00c276266b5e53be31fa19eedebadc9990`

Observed GREEN:

- x64 Release build PASS;
- 0 warnings / 0 errors;
- compiled EXE `--self-test` PASS;
- package creation PASS;
- artifact upload PASS.

Artifact:

- name: `WindowsNoSleep-native-pilot`
- artifact ID: `10489380366`
- uploaded artifact digest:
  `sha256:41bdebfe7c32a831e3840cc4fb36695c8f843d569784dbf5d16d1844d1395a9f`
- distributable nested ZIP SHA-256:
  `758dbf9a68a8ca830332feebe7a57722cfa69eb512957590f1aa81627f731b87`
- EXE SHA-256:
  `4EC31D00B718A541021773590423A9385895FBA812964F3912C2983C55F2FB51`
- signing: UNSIGNED PILOT.

This is hosted evidence only. Do NOT call it final EDR verification.

## 9. Current physical gate — IMPORTANT: NOT YET EXECUTED

Authority:

`docs/LOCAL_NATIVE_PILOT_DISPATCH_001.md`

This dispatch is authorized for ONE bounded protected-endpoint compatibility test of the exact native pilot.

As of this handoff, **the owner has NOT completed this physical test**.

The owner began preparing to test, but only reached local file/path organization and a failed `Get-FileHash` invocation because the EXE was not in the current PowerShell directory. No native EXE launch result, AV/EDR result, tray result, or hash-match result has been returned yet.

Do NOT infer PASS or FAIL.

The next Control Tower should continue this exact gate instead of asking the owner to restart the project.

## 10. Exact native pilot physical test scope

Prefer a spare/test laptop.

Security stays ON normally.

Required:
- exact native pilot artifact;
- verify EXE SHA-256 before launch;
- normal non-elevated user;
- double-click EXE;
- observe tray;
- verify Protected;
- open Settings;
- Stop Protection -> Stopped;
- Start Protection -> Protected;
- Exit -> tray disappears;
- observe endpoint security.

Forbidden during this gate:
- admin elevation;
- AV/EDR disabling;
- AV exclusion/allowlist;
- quarantine release to force a pass;
- lid close;
- battery unplug;
- machine sleep/hibernate/restart/shutdown test;
- manual power-policy edits;
- source edits/rebuilds as a substitute for the exact artifact.

If AV/EDR warns, blocks, terminates, quarantines, removes, or remediates the app:
- STOP immediately;
- do not rerun;
- do not rename/repack/rebuild to evade detection;
- preserve allowed evidence;
- report back to Control Tower.

PASS evidence label:

`NATIVE_PILOT_PROTECTED_ENDPOINT_ACCEPTED`

This is NOT yet final `EDR_VERIFIED`, because the later policy/recovery features are absent.

## 11. Owner local-folder preference

The owner explicitly does NOT want repeated Windows No Sleep folders cluttering:

`Documents\ISTW IT Projects`

Preferred organization discussed:

`Documents\ISTW IT Projects\windows_no_sleep\local-verify`

and:

`Documents\ISTW IT Projects\windows_no_sleep\native-pilot-test`

The previous checkout was named:

`windows_no_sleep-local-verify`

Do not claim it was successfully moved; the conversation ended while organizing this layout.

`ScreenSaverDisabler` is legacy/reference and can remain separate. Do not modify it.

The physical pilot does not require a Git clone if using the exact CI artifact. Prefer the exact CI artifact over a local rebuild for the first protected-endpoint compatibility gate.

## 12. Previous physical evidence from the superseded PowerShell build

Useful product/platform facts, but NOT certification of the native binary:

### Dispatch 001
`LOCAL_READ_ONLY_VERIFIED`

Observed owner laptop:
- Windows 11 25H2 family / Modern Standby S0;
- Balanced active scheme;
- LidAction AC/DC = 0/0;
- SleepIdle AC = 0, DC = 1200 seconds;
- Windows critical battery threshold 5%;
- no mutation.

### Dispatch 002
`LOCAL_POLICY_TRANSACTION_VERIFIED`

Observed:
- real SleepIdle DC `1200 -> 0 -> 1200`;
- exact restore proven;
- lid and active scheme unchanged.

### Dispatch 003
`LID_CLOSED_AC_EXTERNAL_DISPLAY_VERIFIED`

Observed:
- real tray app reached PROTECTED;
- lid physically closed about 90 seconds on AC;
- independent heartbeat continued;
- max gap about 1.046 seconds;
- external monitor remained connected.

Do NOT upgrade that result to `HEADLESS_VERIFIED`.

## 13. Important old-test safety finding

The superseded PowerShell `tests/WindowsIntegrationTests.ps1` is not a safe generic physical-laptop command.

At the reviewed old head it could:
- launch the real app with defaults;
- force-kill it;
- remove transient runtime data;
- without proving laptop policy restoration first.

Do not reuse that old PowerShell test as a new native physical test.

## 14. What to do immediately after the native pilot physical result

### If physical pilot PASS

1. Record exact device/build/security context and PASS evidence in Issue #3.
2. Update Issue #1 and `PROGRESS.md`.
3. Continue the SAME branch / SAME DRAFT PR #4. Do not spawn another rewrite lane.
4. Port remaining V1 features in bounded order:
   - Battery Safety;
   - supported shutdown/restart guard;
   - durable recovery journal;
   - ARR;
   - restore-before-protect lifecycle;
   - power-policy transaction port.
5. Before any real policy-write test:
   - independent safety/source review;
   - fresh exact-head CI;
   - new explicit exact-SHA local dispatch.
6. Then prove clean apply/restore before crash recovery.
7. Later prove battery, headless, longer Modern Standby/overnight, and final protected-endpoint package acceptance.

### If physical pilot is BLOCKED/QUARANTINED

1. Stop. No rerun or whitelist.
2. Record exact artifact hash, security product/classification and visible alert evidence.
3. Keep Issue #3 open.
4. Reassess the packaging/runtime direction from evidence.
5. Do not blindly add signing as a supposed cure; signing is a later provenance/deployment tool, not an EDR bypass.

## 15. PR/merge posture

PR #4 is intentionally DRAFT.

Do not merge merely because hosted CI is green.

The native pilot must first pass the physical protected-endpoint gate, and later V1 functionality/recovery must pass their own reviews/tests.

Do not borrow old physical evidence as proof the new EXE is complete.

## 16. Evidence vocabulary

Formal/general:
- `DESIGNED`
- `STATIC_CHECKED`
- `WINDOWS_VERIFIED`
- `LOCAL_VERIFIED`
- `HEADLESS_VERIFIED`
- `LID_VERIFIED`
- `BATTERY_VERIFIED`
- `EDR_VERIFIED`

Current descriptive evidence:
- `LOCAL_READ_ONLY_VERIFIED`
- `LOCAL_POLICY_TRANSACTION_VERIFIED`
- `LID_CLOSED_AC_EXTERNAL_DISPLAY_VERIFIED`

Pending native-pilot PASS label:
- `NATIVE_PILOT_PROTECTED_ENDPOINT_ACCEPTED`

Do not upgrade labels by inference.

## 17. Successor interaction style

The owner prefers concise, direct Indonesian and wants forward motion.

Do not ask them to make technical architecture choices that Control Tower can resolve safely.

When physical action is actually needed, give one exact bounded sequence.

When it is not needed, continue engineering through GitHub without making the owner manually orchestrate agents.

## 18. Current durable orientation at handoff creation

Main orientation before writing this handoff:
`1416c3bafe8aa267c520852d94ab1f117bb0703b`

Active DRAFT PR #4 orientation head:
`46d99c00c276266b5e53be31fa19eedebadc9990`

Latest known state:
**NATIVE PILOT PHYSICAL PROTECTED-ENDPOINT TEST PENDING.**

The successor must fresh-check GitHub because this handoff commit itself moves `main`.

END_OF_CONTROL_TOWER_HANDOFF key=WNS-CT-20260921-NATIVE-PILOT-PENDING-V1 sections=18
