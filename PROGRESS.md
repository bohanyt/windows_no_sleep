# PROGRESS

## [2026-09-14] P1/P2 boundary reached: hosted Windows E2E + recovery transaction green
- Phase: **P1 source-safe core substantially complete; entering P2 physical Windows integration gate**.
- Control Tower issue: `#1`.
- DRAFT PR: `#2` on `feat/v1-portable-tray`.
- Verified implementation head: `af2d807d9966605b221a390885fe5f9d94bcf3d9`.
- New implementation/evidence since the prior entry:
  - full tray process now launches under **Windows PowerShell 5.1** on a hosted Windows Server 2025 runner and reaches `PROTECTED`;
  - `PowerCreateRequest` / `PowerSetRequest(SystemRequired)` succeeds in the real hosted process;
  - `powercfg /requests` observer sees the live power request where permitted;
  - second-launch/single-instance behavior is exercised;
  - forcibly killing the owning process removes the handle-scoped power request;
  - `powercfg /getactivescheme` and full `powercfg /query` are identical before/after the non-mutating E2E, proving this phase did not alter power-plan values;
  - added PowerShell 5.1-safe WinForms/native interop loader after hosted E2E caught an explicit-reference compatibility failure;
  - added read-only `powrprof.dll` provider for active scheme, lid action, sleep-idle, hibernate-idle identity, and critical-battery threshold;
  - hosted read-only API test passes; example runner evidence read High Performance, Sleep idle AC/DC=0, critical battery level 5%;
  - added pure lid/DC temporary-plan builder: lid target `Do Nothing` (`0`) and optional DC sleep-idle target `Never` (`0`); **no hibernate timeout override is planned**;
  - added active-plan race protection so temporary apply refuses if the user changed plans and restore never re-activates an old plan behind the user;
  - added transactional write-ahead recovery module: snapshot is persisted before first mutation, each write is verified, partial apply triggers reverse rollback, failed/incomplete restore preserves recovery evidence, and recovery clears only after exact verification;
  - deterministic fake-provider transaction tests cover success, exact restore, partial-write failure, rollback, incomplete restore preservation, pending recovery, and corrupt recovery fail-closed;
  - current Windows PowerShell 5.1 CI passes **StaticTests + read-only PowerPolicyTests + PolicyTransactionTests + hosted non-mutating Windows E2E**.
- Evidence label:
  - `HOSTED_WINDOWS_E2E_GREEN`
  - `POLICY_TRANSACTION_FAKE_VERIFIED`
  - still **NOT LOCAL_WINDOWS_VERIFIED** and **NOT RELEASE_READY**.
- Important safety state:
  - the real tray app still does **not** apply lid/DC power-plan mutations;
  - lid control remains visibly not claimed as completed in the dev UI;
  - no physical laptop setting has been changed by this Control Tower;
  - local Cursor executor has still not been dispatched.
- Why the next gate needs the physical Windows 11 laptop:
  - hosted runners cannot prove Modern Standby S0 behavior, real lid-close behavior, real AC/DC transitions, battery discharge/safety, headless/display-disconnect behavior, or SentinelOne acceptance;
  - the next mutation proof must test actual `PowerWrite*ValueIndex` + exact restore on the known Windows 11 25H2 laptop under a bounded recovery-first procedure.
- Next:
  1. prepare one safety-bounded local verification harness/dispatch against this exact implementation lineage;
  2. first local pass is read-only capability/snapshot evidence;
  3. only after snapshot evidence, run a short apply/verify/restore smoke for lid/DC values with automatic `finally` restore;
  4. do not perform a long closed-lid/Modern-Standby soak until apply+restore proof is clean;
  5. keep PR #2 draft until physical Windows and EDR gates are satisfied.

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
  - subsequent Windows PowerShell 5.1 PR check passed;
  - evidence label at this entry was **STATIC_CHECKED only**.
- Deliberately not implemented/claimed yet at this entry:
  - no lid-close power-policy mutation;
  - no DC sleep/hibernate timeout mutation;
  - no physical Modern Standby/lid/headless/battery test;
  - no SentinelOne/EDR verification;
  - no claim of defeating forced Windows Update restarts.
- Local Cursor executor status at this entry: **WAIT / not dispatched**.
- Next: superseded by the hosted-E2E/transaction entry above.

## [2026-09-14] V1 product direction approved; GitHub Control Tower established
- Phase at this entry: **P0 — Authority and plan**.
- Authority added:
  - `docs/PLAN_V1.md`
  - `docs/TEST_PLAN.md`
  - `docs/CONTROL_TOWER.md`
  - refreshed `README.md`
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
- Local executor status at this entry: **WAIT / not dispatched**.
- Next: superseded by the later entries above.

## [2026-09-14] Initial local survey for windows_no_sleep rewrite
- Files: `screenseverdisable/ScreenSaverDisabler.exe` (+ `.config`, `.pdb` only). No local source. No local git. GitHub `bohanyt/windows_no_sleep` exists but is empty (created 2026-09-14, public, admin on this account).
- Done:
  - Identified current app as unmodified `pedrolcl/screensaver-disabler` (C# WinForms, .NET Framework 4.7, BSD-3-Clause, copyright Pedro Lopez-Cabanillas 2020). Local copy is a Debug build dated 2023-11-08, SHA256 `AA0F62E5C00A3CF2BB82DDC1FA8373F66F8DD956D0A8A94A90705261A6E3B044`, 9216 bytes.
  - Logic is a one-shot `SetThreadExecutionState(ES_DISPLAY_REQUIRED | ES_CONTINUOUS)` while a checkbox is on; clears with `ES_CONTINUOUS` on uncheck/close. Does **not** set `ES_SYSTEM_REQUIRED`. No timer refresh, no resume handler, no tray, no autostart.
  - This laptop: Windows 11 Pro for Workstations **25H2**, build `26200.9445`, Modern Standby S0 only (no S3). Display off AC=never / DC=10min. Sleep AC=never / DC=20min. Currently on AC, battery 100%. App not running. Screensaver flag active but no `.scr` set. `.NET Framework 4.8` + SDK 8.0.421 present. Not admin. `powercfg /requests` denied without elevation. PowerToys not installed. `gh` CLI not installed.
- Decisions:
  - Do not run the old EXE or change power settings until planner + user agree a test plan.
  - Treat this as a rewrite, not a binary patch. Keep original license attribution in mind if any original code is reused.
- Next: superseded by the approved V1 authority above.

## [2026-09-14] Publish survey docs to GitHub
- Files: README.md, PROGRESS.md, .gitignore, legacy/LICENSE, legacy/README.md, screenseverdisable/ScreenSaverDisabler.exe.config
- Done: Full local survey published to `bohanyt/windows_no_sleep`. Legacy `.exe`/`.pdb` stay on the laptop (third-party binary). No Windows settings changed.
- Next: superseded by the later entries above.
