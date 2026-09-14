# windows_no_sleep

Small portable Windows utility to keep the **computer and its workloads running** while still allowing the display to dim or turn off.

Primary target: Windows 11 (including Modern Standby / headless NUC use). Windows 10 is a secondary compatibility target where the same supported APIs work without extra complexity.

## Current status

**Planning locked; implementation beginning.**

The old local `ScreenSaverDisabler.exe` is a third-party 2020-era WinForms app from `pedrolcl/screensaver-disabler`. It only makes a one-shot `SetThreadExecutionState(ES_DISPLAY_REQUIRED | ES_CONTINUOUS)` call and is not the design we are carrying forward.

The V1 rewrite is a clean implementation. GitHub is the source of truth.

### Read first

1. [`docs/PLAN_V1.md`](docs/PLAN_V1.md) — product behavior, architecture, safety rules, implementation phases
2. [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md) — safe Windows/Modern Standby/lid/battery/EDR test contract
3. [`docs/CONTROL_TOWER.md`](docs/CONTROL_TOWER.md) — GitHub authority + daily Control Tower handoff rules
4. [`PROGRESS.md`](PROGRESS.md) — current execution state

---

## V1 behavior

Normal operator flow:

```text
copy small folder
    -> double-click launcher
    -> protection starts immediately
    -> no settings window at launch
    -> tray icon appears
    -> click tray icon for advanced settings/status
```

Default Protection aims to:

- keep the system/workloads running through normal idle sleep/standby;
- keep headless/display-off NUC/desktop workloads running;
- allow the display to dim/turn off normally;
- protect on AC and battery until Battery Safety takes priority;
- keep a laptop running with lid closed where a safe temporary lid override is available;
- prevent ordinary idle hibernation while Protection is active;
- resist normal/unattended shutdown/restart attempts while Windows honors the application shutdown-block contract;
- restore every temporary power-policy value it changed.

Default display behavior: **display may turn off**. This is a system-awake tool, not a force-the-monitor-on tool.

Battery Safety default: 15% base threshold, with Windows/OEM critical battery safety remaining authoritative.

---

## Important non-goals

The app must not:

- disable Windows Update/Medic/BITS services;
- disable hibernation globally or delete `hiberfil.sys`;
- permanently set sleep/lid/hibernate values to Never/Do Nothing;
- replace or permanently switch the active power plan;
- change power-button or critical-battery actions;
- use fake keyboard/mouse input;
- install a driver/service in V1;
- bypass AppLocker/WDAC/SentinelOne policy;
- claim it can defeat a forced admin/OS/firmware shutdown.

The goal is practical 24/7 continuity for normal unattended operation, not fighting Windows at any cost.

---

## Packaging direction

Owner preference is a small portable folder and avoiding a custom unsigned `.exe` if a transparent source-first package works reliably on the intended endpoint-security image.

Initial implementation lane:

```text
WindowsNoSleep/
  WindowsNoSleep.cmd
  WindowsNoSleep.ps1
```

No encoded payloads, obfuscation, persistent execution-policy changes, or security bypass tricks. Real PowerShell/EDR compatibility is an explicit release gate. If organizational policy blocks this lane, packaging will be reconsidered rather than evaded.

---

## Legacy survey

Initial local survey date: 2026-09-14.

Local workspace:

`C:\Users\vincentius\Documents\ISTW IT Projects\ScreenSaverDisabler`

Legacy local files:

```text
screenseverdisable/
  ScreenSaverDisabler.exe         9216 bytes, 2023-11-08 08:36
  ScreenSaverDisabler.exe.config  .NET Framework 4.7
  ScreenSaverDisabler.pdb         Debug symbols
```

Legacy binary identity:

| Field | Value |
|---|---|
| Assembly | `ScreenSaverDisabler, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null` |
| PE | AnyCPU MSIL |
| Target | `.NETFramework,Version=v4.7` |
| SHA256 | `AA0F62E5C00A3CF2BB82DDC1FA8373F66F8DD956D0A8A94A90705261A6E3B044` |
| Original project | `pedrolcl/screensaver-disabler` |
| License | BSD-3-Clause |

Exact legacy keep-awake logic:

```csharp
SetThreadExecutionState(ES_DISPLAY_REQUIRED | ES_CONTINUOUS); // on
SetThreadExecutionState(ES_CONTINUOUS);                       // off / close
```

It does not use `ES_SYSTEM_REQUIRED`, `PowerCreateRequest`, timers, resume handling, tray behavior, or restart protection.

The legacy `.exe` and `.pdb` remain local and are not source for the rewrite.

---

## Current Windows 11 physical test machine baseline

Surveyed while non-elevated:

| Item | Value |
|---|---|
| OS | Windows 11 Pro for Workstations 25H2 |
| Build | `10.0.26200.9445` |
| Arch | x64 |
| Sleep model | S0 Low Power Idle / Modern Standby only; no S3 |
| Active plan | Balanced (`381b4222-f694-41f0-9685-ff5bb260df2e`) |
| Display off AC | Never |
| Display off DC | 10 min |
| Sleep AC | Never |
| Sleep DC | 20 min |
| Battery | present |
| .NET Framework | 4.8 |
| .NET SDK | 8.0.421 |
| `powercfg /requests` | requires elevated observer on this machine |

This baseline must be refreshed before mutating integration tests. Do not assume it stays unchanged.

---

## Roles

| Role | Responsibility |
|---|---|
| Owner | product intent / approval |
| Control Tower | plan, GitHub authority, implementation orchestration, review |
| Local Cursor agent | physical Windows execution/test only when explicitly dispatched |

This project is intentionally kept single-owner/small-agent by default. See [`docs/CONTROL_TOWER.md`](docs/CONTROL_TOWER.md).
