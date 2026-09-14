# PROGRESS

## [2026-09-14] P2 Dispatch 001 PASS — read-only laptop probe verified; Dispatch 002 authorized
- Phase: **P2 — physical Windows integration, bounded mutation gate**.
- Control Tower issue: `#1`.
- DRAFT PR: `#2` on `feat/v1-portable-tray`.
- Exact tested implementation SHA: `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`.
- Dispatch 001 was executed in a separate clean checkout, detached at the exact SHA, normal non-elevated user, AC connected, lid open.
- Local read-only evidence from the owner's Windows 11 25H2 Modern Standby laptop:
  - PowerShell `5.1.26100.9444` executed the harness and `Add-Type` without endpoint-security blocking;
  - active scheme = Balanced `381b4222-f694-41f0-9685-ff5bb260df2e`;
  - lid action = `AC=0 / DC=0` (`Do Nothing`) already, therefore **no lid-policy mutation is needed on this laptop**;
  - sleep idle = `AC=0 / DC=1200` seconds;
  - critical battery level exposed by Windows = `5%`;
  - battery present, on AC, 100% during probe;
  - `powercfg /a` confirms **S0 Low Power Idle / Modern Standby, network connected**; S3, Hibernate, Hybrid Sleep and Fast Startup unavailable;
  - `powercfg /requests` non-elevated returns Access Denied, matching the initial survey; this is an observer limitation, not an app failure;
  - proposed temporary policy plan contained exactly **one** item: `SleepIdle`, DC only, `1200 -> 0`; no LidAction change;
  - `MutationAttempted=false`, `MutationApplied=false`, `Outcome=PROBE_ONLY`;
  - tracked git status remained clean; only ignored local evidence artifacts were created.
- Important interpretation:
  - the laptop's existing lid configuration already satisfies the owner's desired “lid closed does not itself trigger sleep” policy;
  - the remaining known timer risk on battery is the 20-minute DC idle-sleep value;
  - therefore the first real write proof should touch **only** that single DC SleepIdle value and immediately restore it.
- Evidence status:
  - `HOSTED_WINDOWS_E2E_GREEN`;
  - `POLICY_TRANSACTION_FAKE_VERIFIED`;
  - physical **read-only capability/policy snapshot verified on the local laptop**;
  - still **NOT** lid-behavior verified, Modern-Standby soak verified, battery verified, headless verified, release-package EDR verified, or release ready.
- Authority detail: `docs/LOCAL_DISPATCH_001.md` lives on `main`, while the implementation checkout intentionally remained detached at exact implementation SHA `63ea8c99...`; the dispatch document was therefore not expected to exist inside that historical implementation tree.
- Dispatch 002 authority: `docs/LOCAL_DISPATCH_002.md` on `main`.
- Local Cursor executor status: **DISPATCH 002 READY**.
- Dispatch 002 permits exactly one narrow policy transaction, only after a fresh preflight Probe still matches the verified snapshot:
  - temporary `SleepIdle DC 1200 -> 0`;
  - verify;
  - hold about 3 seconds;
  - exact restore `0 -> 1200`;
  - re-read and prove restoration;
  - no lid mutation, no AC timeout change, no sleep/lid/battery behavioral test.
- Next:
  1. owner relays Dispatch 002 to local Cursor;
  2. executor runs fresh Probe and proceeds only if proposed changes are exactly one DC SleepIdle change;
  3. executor runs the bounded ApplyRestoreSmoke and returns before/after/result evidence;
  4. Control Tower reviews exact restoration before authorizing any physical lid/Modern-Standby/DC behavior test.

## [2026-09-14] P2 Dispatch 001 ready — physical read-only probe only
- Phase at this entry: **P2 — physical Windows integration, read-only gate**.
- Control Tower issue: `#1`.
- DRAFT PR: `#2` on `feat/v1-portable-tray`.
- Exact implementation SHA authorized for the first local probe: `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`.
- Added and hardened `tools/LocalWindowsVerification.ps1`:
  - default mode is `Probe`, which reads capability/policy state and writes evidence JSON only;
  - mutation mode is separately gated by `ApplyRestoreSmoke` + an explicit acknowledgement switch and was **not authorized by Dispatch 001**;
  - probe captures active scheme, lid AC/DC, sleep-idle AC/DC, critical-battery level, AC/battery status, `powercfg /a`, and `powercfg /requests` result;
  - local evidence is written only under ignored `artifacts/local-verification/`;
  - mutation-mode cleanup was hardened so restore errors do not prevent evidence capture and null/unreadable after-state fails closed;
  - all PowerShell source/tests/tools are parser-checked under Windows PowerShell 5.1 CI.
- Hosted evidence for exact SHA `63ea8c99bd90b5416d00d6bec827a8b9e27b8218` is green:
  - StaticTests: PASS;
  - read-only PowerPolicyTests: PASS;
  - PolicyTransactionTests: PASS;
  - hosted non-mutating Windows E2E: PASS.
- Local authority: `docs/LOCAL_DISPATCH_001.md`.
- Local Cursor executor status at this entry: **DISPATCH READY — PROBE ONLY**.
- Next: superseded by the successful Dispatch 001 result above.

## [2026-09-14] P1/P2 boundary reached: hosted Windows E2E + recovery transaction green
- Phase: **P1 source-safe core substantially complete; entering P2 physical Windows integration gate**.
- Control Tower issue: `#1`.
- DRAFT PR: `#2` on `feat/v1-portable-tray`.
- Verified implementation head at this entry: `af2d807d9966605b221a390885fe5f9d94bcf3d9`.
- New implementation/evidence since the prior entry:
  - full tray process launches under **Windows PowerShell 5.1** on a hosted Windows Server 2025 runner and reaches `PROTECTED`;
  - `PowerCreateRequest` / `PowerSetRequest(SystemRequired)` succeeds in the real hosted process;
  - `powercfg /requests` observer sees the live power request where permitted;
  - second-launch/single-instance behavior is exercised;
  - forcibly killing the owning process removes the handle-scoped power request;
  - `powercfg /getactivescheme` and full `powercfg /query` are identical before/after the non-mutating E2E, proving this phase did not alter power-plan values;
  - added PowerShell 5.1-safe WinForms/native interop loader after hosted E2E caught an explicit-reference compatibility failure;
  - added read-only `powrprof.dll` provider for active scheme, lid action, sleep-idle, hibernate-idle identity, and critical-battery threshold;
  - hosted read-only API test passes;
  - added pure lid/DC temporary-plan builder: lid target `Do Nothing` (`0`) and optional DC sleep-idle target `Never` (`0`); **no hibernate timeout override is planned**;
  - added active-plan race protection so temporary apply refuses if the user changed plans and restore never re-activates an old plan behind the user;
  - added transactional write-ahead recovery module: snapshot is persisted before first mutation, each write is verified, partial apply triggers reverse rollback, failed/incomplete restore preserves recovery evidence, and recovery clears only after exact verification;
  - deterministic fake-provider transaction tests cover success, exact restore, partial-write failure, rollback, incomplete restore preservation, pending recovery, and corrupt recovery fail-closed;
  - current Windows PowerShell 5.1 CI passes **StaticTests + read-only PowerPolicyTests + PolicyTransactionTests + hosted non-mutating Windows E2E**.
- Evidence label:
  - `HOSTED_WINDOWS_E2E_GREEN`;
  - `POLICY_TRANSACTION_FAKE_VERIFIED`.
- Next: superseded by later P2 entries above.

## [2026-09-14] P1 source-safe implementation started; first CI green
- Phase: **P1 — source-safe core**.
- Control Tower issue: `#1`.
- Implementation branch: `feat/v1-portable-tray`.
- DRAFT PR: `#2`.
- Current implementation head at this entry: `329f161f1160d54b415d25f3c1a47b72689b23a9`.
- Added on the implementation branch:
  - `WindowsNoSleep.cmd` quiet double-click launcher using built-in Windows PowerShell 5.1;
  - `WindowsNoSleep.ps1` tray host, small Settings UI, single-instance signaling, SystemRequired power-request source path, normal shutdown/restart guard source path, battery observation and Battery Safety runtime state;
  - `src/WindowsNoSleep.Core.psm1` settings/state/recovery/log helpers;
  - `tests/StaticTests.ps1` parser/core/persistence tests;
  - `.github/workflows/static-checks.yml` on a Windows runner with Windows PowerShell 5.1.
- Evidence:
  - first CI run correctly found a PowerShell 5.1 nullable-value bug in the Battery Safety helper;
  - fixed in `329f161f1160d54b415d25f3c1a47b72689b23a9`;
  - subsequent Windows PowerShell 5.1 PR check passed.
- Next: superseded by later entries above.

## [2026-09-14] V1 product direction approved; GitHub Control Tower established
- Phase at this entry: **P0 — Authority and plan**.
- Authority added:
  - `docs/PLAN_V1.md`
  - `docs/TEST_PLAN.md`
  - `docs/CONTROL_TOWER.md`
  - refreshed `README.md`.
- Owner-approved direction:
  - tool keeps the **computer/workloads** running; display may dim/turn off;
  - intended for Windows 11 across mixed versions, especially Modern Standby and headless/display-off NUC use; Windows 10 secondary target;
  - double-click launcher starts Protection immediately with no initial settings window;
  - tray icon appears; clicking it opens advanced Settings/status;
  - default protection covers idle sleep/standby/hibernate as far as supported mechanisms allow;
  - laptop battery protection is ON until Battery Safety takes priority;
  - base Battery Safety threshold is 15%, while Windows/OEM critical battery behavior remains authoritative;
  - laptop lid-close protection is desired where safe: temporary `Do Nothing` transaction with exact snapshot/restore, never permanent;
  - normal/unattended shutdown/restart blocker is in scope; forced OS/admin/firmware restart is an accepted platform boundary;
  - do not disable Windows Update/Medic/BITS, hibernation feature, critical-battery action, power-button action, or create a permanent power plan;
  - default display forcing is OFF;
  - autostart exists as an optional setting and defaults OFF;
  - packaging preference is portable source-first (`.cmd` + `.ps1`) without obfuscation/bypass tricks; actual PowerShell/EDR compatibility is a required release gate.
- Architecture decision:
  - primary awake contract: `PowerCreateRequest` / `PowerSetRequest` with `PowerRequestSystemRequired`;
  - do not add `SetThreadExecutionState` as a second mechanism without evidence that a tested compatibility failure requires it;
  - Modern Standby/DC and closed-lid indefinite operation may require narrowly scoped temporary active-plan overrides, but these are forbidden until snapshot/restore logic and local test dispatch are ready;
  - shutdown guard uses supported application shutdown-block semantics, not update-service sabotage.
- Staffing:
  - project classified as **small utility / high integration sensitivity**;
  - default: one Control Tower + one implementation owner + local Windows executor only when hardware/OS proof is needed;
  - no swarm by default.
- Next: superseded by later entries above.

## [2026-09-14] Initial local survey for windows_no_sleep rewrite
- Files: `screenseverdisable/ScreenSaverDisabler.exe` (+ `.config`, `.pdb` only). No local source. No local git.
- Done:
  - identified current app as unmodified `pedrolcl/screensaver-disabler`;
  - local laptop surveyed as Windows 11 Pro for Workstations 25H2 build 26200.9445 with Modern Standby S0 only;
  - no Windows settings changed during survey.
- Next: superseded by later entries above.
