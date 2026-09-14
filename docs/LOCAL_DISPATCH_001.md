# LOCAL DISPATCH 001 — READ-ONLY WINDOWS PROBE

Status: **AUTHORIZED — PROBE ONLY**  
Date: 2026-09-14  
Control Tower issue: #1  
Implementation PR: #2  
Implementation branch: `feat/v1-portable-tray`  
Exact required implementation SHA: `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`

This dispatch authorizes the physical Windows Cursor executor to perform one bounded **read-only power-policy probe**. It does **not** authorize power-policy mutation, code edits, commits, pushes, lid-close testing, battery discharge testing, sleep/restart testing, or EDR bypass.

---

## Purpose

Hosted Windows evidence is already green for the non-mutating tray/app path and transaction logic. The remaining unknowns now depend on the owner's real Windows 11 25H2 Modern Standby laptop.

This first local pass answers only:

1. Does the exact source/harness execute under the endpoint's normal user + security policy?
2. What is the exact active power scheme?
3. Can the supported power APIs read the current lid AC/DC action?
4. Can they read idle-sleep AC/DC values?
5. What critical battery threshold is exposed?
6. Does `powercfg /a` confirm the expected Modern Standby state?
7. Is `powercfg /requests` observable non-elevated, or does it return access denied as previously surveyed?
8. What temporary changes *would* be proposed later, without applying any of them now?

---

## Fresh checkout rule

Do not work in or modify the legacy `ScreenSaverDisabler` folder.

Use a separate clean checkout. The repo is public, so no GitHub write permission is needed for this dispatch.

Example PowerShell sequence:

```powershell
git clone https://github.com/bohanyt/windows_no_sleep.git windows_no_sleep-local-verify
cd windows_no_sleep-local-verify
git fetch origin feat/v1-portable-tray
git checkout --detach 63ea8c99bd90b5416d00d6bec827a8b9e27b8218
git rev-parse HEAD
```

If the repository is already present in a separate clean test checkout, fetch and detach at the exact SHA instead of cloning again.

**STOP** if `git rev-parse HEAD` is not exactly:

`63ea8c99bd90b5416d00d6bec827a8b9e27b8218`

Do not substitute a newer SHA without a new Control Tower dispatch.

---

## Required execution context

- normal user session;
- **not elevated / not Run as Administrator**;
- keep the laptop connected to AC for this probe;
- do not close the lid during this dispatch;
- do not intentionally sleep, hibernate, restart, or shut down the machine;
- do not change execution policy;
- do not disable or bypass SentinelOne/EDR/AppLocker/Defender or any security product.

If PowerShell execution or Add-Type is blocked by endpoint policy/security, **STOP and report the exact block/error**. That is valuable compatibility evidence. Do not bypass it.

---

## Only authorized test command

From the detached exact SHA:

```powershell
powershell.exe -NoProfile -File .\tools\LocalWindowsVerification.ps1 -Mode Probe
```

Do **not** add `-ExecutionPolicy Bypass` or any equivalent.

The default `Probe` mode may create JSON evidence files under the repository's ignored local `artifacts\local-verification\...` directory. That file output is allowed. It must not write Windows power policy.

Expected terminal marker on successful completion:

`LOCAL_WINDOWS_PROBE_COMPLETE`

---

## Explicitly forbidden in Dispatch 001

Do **not**:

- run `-Mode ApplyRestoreSmoke`;
- use `-AcknowledgeTemporaryPowerPolicyChange`;
- run any `powercfg /set*`, `/change`, `/hibernate`, `/setactive`, or other power-setting mutation command;
- edit registry power policy;
- disable Windows Update, Medic, BITS, EDR, Defender, SentinelOne, or related services;
- change lid-close behavior;
- change sleep/hibernate/display timeout;
- change power-button or critical-battery action;
- switch active power plans;
- close the physical laptop lid;
- unplug AC for battery testing;
- trigger Sleep/Hibernate/Shutdown/Restart;
- edit source files;
- commit or push anything;
- use admin elevation to make a blocked read work.

If a read is unavailable without elevation, report it as unavailable.

---

## Evidence to return to Control Tower

Return:

1. exact output of `git rev-parse HEAD`;
2. whether the PowerShell command was allowed by endpoint security;
3. terminal output from the probe;
4. the generated `result.json` and `before.json` contents, or at minimum these exact fields:
   - `OsVersion`
   - `PowerShellVersion`
   - `Elevated`
   - `ActiveSchemeGuid`
   - Lid `AC` / `DC`, or `LidReadError`
   - SleepIdle `AC` / `DC`, or `SleepIdleReadError`
   - `CriticalBatteryPercent`
   - `Power.HasBattery`, `Power.OnAC`, `Power.BatteryPercent`
   - `PowerCfg.AvailableSleepStates`
   - `PowerCfg.Requests` exit code/stdout/stderr
   - `ProposedChanges`
   - `Outcome`
5. `git status --short` after the test. Expected tracked working tree: clean; ignored `artifacts/` is allowed.

The executor may omit/redact `ComputerName` when reporting; it is not needed for acceptance.

---

## Stop conditions

Stop immediately and do not improvise if:

- exact SHA cannot be checked out;
- PowerShell/script/Add-Type is blocked by security policy;
- the harness throws before producing evidence;
- active scheme cannot be read;
- any unexpected Windows setting appears to change;
- the executor is unsure whether a proposed next action is read-only.

Return the evidence/error to Control Tower. A later dispatch will separately authorize a short apply/verify/exact-restore smoke **only after this read-only probe is reviewed**.
