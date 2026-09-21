# PROGRESS

## Current status — 2026-09-17

Phase: **P2 — EDR remediation / native compiled pilot validation**.

GitHub is the source of truth.

### Owner-approved architecture pivot

Issue #3 established a protected-endpoint compatibility failure for the PowerShell-first runtime/recovery path. The owner has approved the replacement direction recorded in `docs/NATIVE_RUNTIME_DECISION.md` on `main`.

The approved native direction is:

- conventional compiled C# WinForms application;
- .NET Framework 4.8;
- portable x64 `WindowsNoSleep.exe`;
- normal non-elevated manifest;
- no PowerShell/CMD/script-host child process in normal operation;
- no embedded/extracted script payload;
- no obfuscation, runtime download, EDR bypass or automatic elevation;
- no signing purchase required for the first pilot.

Approved recovery direction for the later mutating build:

1. durable recovery journal written before any temporary policy mutation;
2. Windows Application Recovery and Restart (`RegisterApplicationRecoveryCallback` / `RegisterApplicationRestart`) for conventional crash/hang recovery where Windows invokes it;
3. restore-before-protect on every normal launch if a journal remains pending.

ARR is best-effort and is not treated as a guarantee for force-kill, EDR termination, power loss or kernel failure. No `RunOnce`, scheduled task, service or hidden recovery helper is currently approved for the native V1 design.

### Implementation lanes

- **Active lane:** `feat/v1-native-winforms` / DRAFT PR #4.
- **Superseded lane:** `feat/v1-portable-tray` / closed DRAFT PR #2. It remains reference/history only.
- Issue #3 remains open.
- Old local Dispatch 004 remains cancelled/HOLD and must not be executed.

### Native Stage B pilot

Exact current native pilot head: `46d99c00c276266b5e53be31fa19eedebadc9990`.

Implemented at that head:

- `native/WindowsNoSleep/WindowsNoSleep.csproj` — x64 .NET Framework 4.8 WinForms executable;
- immediate direct `PowerCreateRequest` / `PowerSetRequest(PowerRequestSystemRequired)` lease;
- tray icon;
- small Settings/status window;
- Start/Stop Protection;
- Exit cleanup;
- `--self-test` path that acquires/releases only the SystemRequired lease;
- ordinary `asInvoker` manifest;
- CI Release build, exact package artifact and SHA-256 recording.

The pilot deliberately has **no**:

- lid-action mutation;
- AC/DC sleep-timeout mutation;
- registry startup entry;
- `RunOnce` recovery;
- recovery journal (not needed yet because the pilot makes no persistent policy mutation);
- shutdown guard;
- Battery Safety controller;
- installer;
- signing requirement;
- AV/EDR exclusion or bypass.

### Hosted evidence for the native pilot

GitHub Actions run `35203872675` on exact head `46d99c00c276266b5e53be31fa19eedebadc9990` is GREEN:

- x64 Release build: PASS, 0 warnings / 0 errors;
- exact compiled EXE `--self-test`: PASS;
- package creation: PASS;
- artifact upload: PASS.

Published workflow artifact:

- artifact name: `WindowsNoSleep-native-pilot`;
- artifact ID: `10489380366`;
- uploaded artifact digest: `sha256:41bdebfe7c32a831e3840cc4fb36695c8f843d569784dbf5d16d1844d1395a9f`;
- distributable nested ZIP SHA-256: `758dbf9a68a8ca830332feebe7a57722cfa69eb512957590f1aa81627f731b87`;
- `WindowsNoSleep.exe` SHA-256: `4EC31D00B718A541021773590423A9385895FBA812964F3912C2983C55F2FB51`;
- signing status: **UNSIGNED PILOT**.

This is hosted build/runtime evidence only. It is **not** `EDR_VERIFIED` and does not inherit physical acceptance labels from the old PowerShell build.

### Issue #3 safety findings that remain authoritative

- The original EDR report quarantined multiple PowerShell/source files plus `WindowsNoSleepRecovery` startup state. Root cause attribution to any single behavior is still unproven.
- The old `tests/WindowsIntegrationTests.ps1` is not a safe generic laptop integration command because it can force-kill the real production app and remove transient runtime data without first proving restoration on a battery-equipped machine.
- Do not rerun the old quarantined PowerShell path on the affected endpoint.
- Do not disable or bypass endpoint security or add broad exclusions merely to obtain a pass.

### Previously verified physical evidence — reference only for the new binary

The old PowerShell build established useful product/platform facts:

- `LOCAL_READ_ONLY_VERIFIED` — Windows 11 25H2 / Modern Standby S0 baseline;
- `LOCAL_POLICY_TRANSACTION_VERIFIED` — real `SleepIdle DC 1200 -> 0 -> 1200` exact restore;
- `LID_CLOSED_AC_EXTERNAL_DISPLAY_VERIFIED` — lid closed on AC with external display attached; ~1 Hz workload continued with max gap ~1.046 s.

Those facts inform the port, but they do **not** certify PR #4 or the new EXE.

### Local executor status

**WAIT until a new native-pilot dispatch is explicitly issued.**

The next physical step should use the exact CI artifact above on an approved protected endpoint with normal security policy, no exclusions, no admin elevation, and no power-policy mutation. A security detection immediately stops the trial.

If the exact native pilot is accepted, continue porting the remaining V1 features in the same branch/PR #4. Do not spawn a competing rewrite.

### Remaining gates

- exact unsigned native pilot accepted on the agreed protected endpoint;
- Battery Safety port;
- supported shutdown/restart guard port;
- durable recovery journal + ARR implementation and independent safety review;
- bounded real policy apply/restore on the native build;
- crash/next-launch recovery proof;
- `BATTERY_VERIFIED` on the native build;
- `HEADLESS_VERIFIED` on the native build;
- longer Modern Standby/overnight soak;
- final protected-endpoint package acceptance and any later signing/deployment decision;
- independent release review before native PR is ready/merged.


### Native pilot local dispatch

`docs/LOCAL_NATIVE_PILOT_DISPATCH_001.md` is now **AUTHORIZED** for one non-mutating protected-endpoint compatibility test using the exact CI artifact from run `35203872675` / source head `46d99c00c276266b5e53be31fa19eedebadc9990`.

The test keeps normal endpoint security enabled, requires the exact EXE SHA-256 `4EC31D00B718A541021773590423A9385895FBA812964F3912C2983C55F2FB51`, and exercises only tray launch, Protected -> Stopped -> Protected, and Exit. It authorizes no power-policy mutation, registry persistence, elevation, security exclusion, battery/lid test, or recovery test.

Any warning/block/quarantine immediately stops the trial; do not rerun or whitelist.



### Successor Control Tower handoff — 2026-09-21

Durable full successor handoff:

`docs/CONTROL_TOWER_HANDOFF_20260921.md`

Read it through this exact sentinel before claiming full handoff consumption:

`END_OF_CONTROL_TOWER_HANDOFF key=WNS-CT-20260921-NATIVE-PILOT-PENDING-V1 sections=18`

Current handoff posture: **native pilot physical protected-endpoint test is still PENDING, not PASS/FAIL.**

The owner had only begun local artifact/path preparation and had not yet returned a matching EXE hash or runtime/EDR result. Continue `docs/LOCAL_NATIVE_PILOT_DISPATCH_001.md`; do not restart architecture work or revive the PowerShell lane.
