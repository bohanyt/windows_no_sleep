# LOCAL DISPATCH 003 — AC CLOSED-LID WORKLOAD WITNESS

Status: **AUTHORIZED — NON-MUTATING PHYSICAL LID TEST ONLY**  
Date: 2026-09-14  
Control Tower issue: #1  
Implementation PR: #2  
Implementation branch: `feat/v1-portable-tray`  
Exact required implementation SHA: `213c37a86a80d17e58116dee9b4b3ac86f16184f`

This dispatch authorizes one short physical closed-lid witness on the owner's known Windows 11 25H2 laptop. It does **not** authorize any power-policy mutation, battery test, source edit, commit, push, elevation, or security bypass.

## Why this test is safe enough now

Dispatch 001 proved the laptop already has lid action `AC=0 / DC=0` (`Do Nothing`). Dispatch 002 proved the only candidate temporary DC SleepIdle write can be applied and restored exactly, but that transaction is not yet wired into the production tray app.

This test therefore stays on AC and does not need or perform any power-policy write. Its purpose is only to prove that when the physical lid/internal display is closed, a real independent workload continues to receive execution time while the real tray app remains active.

## Fresh checkout rule

Use the existing separate verification checkout if clean. Do not work in the legacy `ScreenSaverDisabler` workspace.

Fetch and detach at exactly:

`213c37a86a80d17e58116dee9b4b3ac86f16184f`

Then prove:

```powershell
git rev-parse HEAD
git status --short
```

STOP if HEAD differs or tracked status is not clean.

## Required execution context

- normal user session;
- not elevated;
- AC connected for the entire test;
- battery may remain installed but do not unplug AC;
- do not change execution policy;
- do not bypass SentinelOne/EDR/AppLocker/Defender;
- do not run manual `powercfg` mutation commands;
- do not change any Windows power setting.

## Mandatory baseline

Before closing the lid, the harness itself will verify all of these:

- active scheme = Balanced `381b4222-f694-41f0-9685-ff5bb260df2e`;
- lid action = `AC=0 / DC=0`;
- sleep idle = `AC=0 / DC=1200`;
- session is non-elevated;
- AC is online.

If any baseline differs, the harness must STOP before the physical test.

## Authorized command

From the exact detached SHA:

```powershell
powershell.exe -NoProfile -File .\tools\LocalLidWitness.ps1 -WitnessSeconds 120
```

Do not add ExecutionPolicy bypass or other switches.

The harness launches the real `WindowsNoSleep.ps1` tray process with isolated local runtime storage, waits until the app logs `PROTECTED`, and then prints:

`LOCAL_LID_WITNESS_READY`

Only after that marker:

1. physically close the laptop lid promptly;
2. keep it closed for about **90 seconds**, timed externally (for example with a phone); do not unplug AC;
3. reopen the lid;
4. let the harness finish its 120-second witness window.

The harness writes a heartbeat every second while the lid is closed. If Windows enters standby/sleep or execution stops, the resulting timestamp gap will expose that.

Expected success markers:

- `LOCAL_LID_WITNESS_COMPLETE`
- outcome `LID_CLOSED_WORKLOAD_CONTINUED`
- maximum heartbeat gap <= 5 seconds.

The harness force-stops only its own test tray process during cleanup. At this implementation SHA the production tray app does not own any power-policy transaction, so this cleanup cannot leave a temporary power-plan override behind.

## Explicitly forbidden

Do not:

- run `LocalWindowsVerification.ps1 -Mode ApplyRestoreSmoke` again;
- modify LidAction or SleepIdle;
- unplug AC;
- intentionally trigger Sleep/Hibernate/Restart/Shutdown;
- change display timeout;
- change hibernation configuration;
- switch power plans;
- use admin elevation;
- bypass security software;
- edit tracked source;
- commit or push.

If the laptop becomes unusually hot while closed, reopen the lid and stop the test; thermal safety wins.

## Evidence to return

Return:

1. exact `git rev-parse HEAD`;
2. `git status --short` before and after;
3. complete terminal output;
4. generated `result.json`;
5. `heartbeat.txt` summary: sample count and maximum observed gap;
6. whether the tray/app process reached `PROTECTED` before lid close;
7. any endpoint-security prompt/block;
8. whether the machine was responsive immediately after reopening.

Expected final Windows policy remains exactly:

- Balanced scheme;
- Lid `AC=0 / DC=0`;
- SleepIdle `AC=0 / DC=1200`.

## Stop conditions

Stop and report without improvising if:

- exact SHA cannot be checked out;
- baseline differs;
- PowerShell/Add-Type is blocked;
- tray app cannot reach `PROTECTED`;
- AC disconnects;
- laptop shows thermal concern;
- the executor is unsure whether a next action would mutate Windows policy.

End report with:

`CONTROL_TOWER_READY`
