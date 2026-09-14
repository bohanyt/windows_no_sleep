# PROGRESS

## [2026-09-14] P1 source-safe implementation started; first CI green
- Phase: **P1 — source-safe core**.
- Control Tower issue: `#1`.
- Implementation branch: `feat/v1-portable-tray`.
- DRAFT PR: `#2`.
- Current implementation head: `329f161f1160d54b415d25f3c1a47b72689b23a9`.
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
  - current evidence label is **STATIC_CHECKED only**.
- Deliberately not implemented/claimed yet:
  - no lid-close power-policy mutation;
  - no DC sleep/hibernate timeout mutation;
  - no real recovery restore provider;
  - no physical Modern Standby/lid/headless/battery test;
  - no SentinelOne/EDR verification;
  - no claim of defeating forced Windows Update restarts.
- Local Cursor executor status: **WAIT / not dispatched**. No physical laptop power settings have been changed by this implementation work.
- Next:
  1. continue bounded P1 review/hardening on PR #2;
  2. move to non-mutating Windows integration proof (power request / tray / shutdown guard) before any power-plan mutation;
  3. request the local Cursor test machine only when GitHub/hosted-Windows evidence cannot prove the required behavior;
  4. do not begin lid/DC mutation until recovery transaction logic is complete and a safety-bounded local dispatch exists.

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
- Next: superseded by the P1 entry above.

## [2026-09-14] Initial local survey for windows_no_sleep rewrite
- Files: `screenseverdisable/ScreenSaverDisabler.exe` (+ `.config`, `.pdb` only). No local source. No local git. GitHub `bohanyt/windows_no_sleep` exists but is empty (created 2026-09-14, public, admin on this account).
- Done:
  - Identified current app as unmodified `pedrolcl/screensaver-disabler` (C# WinForms, .NET Framework 4.7, BSD-3-Clause, copyright Pedro Lopez-Cabanillas 2020). Local copy is a Debug build dated 2023-11-08, SHA256 `AA0F62E5C00A3CF2BB82DDC1FA8373F66F8DD956D0A8A94A90705261A6E3B044`, 9216 bytes.
  - Logic is a one-shot `SetThreadExecutionState(ES_DISPLAY_REQUIRED | ES_CONTINUOUS)` while a checkbox is on; clears with `ES_CONTINUOUS` on uncheck/close. Does **not** set `ES_SYSTEM_REQUIRED`. No timer refresh, no resume handler, no tray, no autostart.
  - This laptop: Windows 11 Pro for Workstations 25H2, build `26200.9445`, Modern Standby S0 only (no S3). Display off AC=never / DC=10min. Sleep AC=never / DC=20min. Currently on AC, battery 100%. App not running. Screensaver flag active but no `.scr` set. `.NET Framework 4.8` + SDK 8.0.421 present. Not admin. `powercfg /requests` denied without elevation. PowerToys not installed. `gh` CLI not installed.
- Decisions:
  - Do not run the old EXE or change power settings until planner + user agree a test plan.
  - Treat this as a rewrite, not a binary patch. Keep original license attribution in mind if any original code is reused.
- Next: superseded by the approved V1 authority above.

## [2026-09-14] Publish survey docs to GitHub
- Files: README.md, PROGRESS.md, .gitignore, legacy/LICENSE, legacy/README.md, screenseverdisable/ScreenSaverDisabler.exe.config
- Done: Full local survey published to `bohanyt/windows_no_sleep`. Legacy `.exe`/`.pdb` stay on the laptop (third-party binary). No Windows settings changed.
- Next: superseded by the approved V1 authority above.
