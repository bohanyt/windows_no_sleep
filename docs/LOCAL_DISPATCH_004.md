# LOCAL DISPATCH 004 — PRODUCTION POLICY + CRASH RECOVERY WITNESS

Status: **AUTHORIZED — ONE BOUNDED PRODUCTION RECOVERY TEST**  
Date: 2026-09-14  
Control Tower issue: #1  
Implementation PR: #2  
Implementation branch: `feat/v1-portable-tray`  
Exact required implementation SHA: `8059f92f51702c35646e94c8b1afe1e1e3c96934`

GitHub is source of truth. This dispatch authorizes one automated physical-Windows witness of the production tray runtime's temporary power-policy lifecycle and crash recovery.

It does **not** authorize battery unplug, closed-lid testing, manual powercfg writes, source edits, elevation, or security bypass.

## Purpose

Previous physical evidence already proved:

- the owner laptop baseline is Balanced `381b4222-f694-41f0-9685-ff5bb260df2e`;
- lid action is already `AC=0 / DC=0`;
- SleepIdle is `AC=0 / DC=1200`;
- a direct transaction can apply `SleepIdle DC 1200 -> 0` and restore exactly;
- an AC closed-lid workload witness continued with ~1 second heartbeat cadence, with an external monitor attached.

The production tray runtime is now wired to the same transaction/recovery system. Dispatch 004 proves the **real production app**, not the direct transaction harness, does all of the following:

1. reaches `PROTECTED`;
2. changes only SleepIdle DC `1200 -> 0` on this laptop;
3. persists exact recovery data before/while that temporary value is active;
4. installs a temporary HKCU recovery startup hook;
5. survives an intentional force-kill with recovery state still intact;
6. restores exact originals through the production `-RecoveryOnly` path;
7. removes recovery state and the recovery startup hook after verified restore.

## Checkout rule

Use the existing separate `windows_no_sleep-local-verify` checkout. Do not work in or modify the legacy `ScreenSaverDisabler` workspace.

Fetch and detach at exactly:

`8059f92f51702c35646e94c8b1afe1e1e3c96934`

Prove before execution:

```powershell
git rev-parse HEAD
git status --short
```

STOP if HEAD differs or tracked status is not clean.

## Required execution context

- normal non-elevated user session;
- AC connected for the entire test;
- lid stays physically open;
- do not unplug AC;
- do not sleep/hibernate/restart/shutdown the machine;
- do not change execution policy;
- do not bypass SentinelOne/EDR/AppLocker/Defender;
- do not manually edit Windows power policy or registry;
- do not edit source, commit, or push.

The harness itself must refuse to start if `%LOCALAPPDATA%\WindowsNoSleep` already exists or if a previous `WindowsNoSleepRecovery` RunOnce value already exists. If either exists, STOP and report it; do not delete existing user/recovery data just to make the test pass.

## Authorized command

From the exact detached SHA, run exactly once:

```powershell
powershell.exe -NoProfile -File .\tools\LocalProductionRecoveryWitness.ps1
```

Do not add `-ExecutionPolicy Bypass` or other switches.

## Authorized temporary changes

The production app/harness may temporarily create only:

- `%LOCALAPPDATA%\WindowsNoSleep\...` runtime/recovery files;
- HKCU `Software\Microsoft\Windows\CurrentVersion\RunOnce` value `WindowsNoSleepRecovery`;
- the previously verified single power-policy change `SleepIdle DC 1200 -> 0`.

On this laptop it must **not** alter:

- LidAction (`AC=0 / DC=0` must remain unchanged);
- SleepIdle AC (`0` must remain unchanged);
- active power scheme;
- display timeout;
- hibernation configuration;
- critical-battery policy;
- power-button action.

## Expected terminal milestones

Expected successful sequence:

```text
PRODUCTION_POLICY_ACTIVE_VERIFIED
PRODUCTION_CRASH_STATE_VERIFIED
LOCAL_PRODUCTION_RECOVERY_COMPLETE
```

The harness intentionally force-kills only the tray process after proving production policy is active. This is deliberate crash simulation, not a machine shutdown.

## Expected evidence

`result.json` must show:

- `Outcome = PRODUCTION_CRASH_RECOVERY_VERIFIED`;
- while protected: SleepIdle `AC=0 / DC=0`;
- after forced process crash: SleepIdle DC still `0`;
- recovery status `Pending` before and after crash;
- recovery startup hook present while active and after crash;
- after RecoveryOnly: SleepIdle restored exactly `AC=0 / DC=1200`;
- Lid remains exactly `AC=0 / DC=0` throughout;
- active scheme remains Balanced `381b4222-f694-41f0-9685-ff5bb260df2e`;
- final recovery status `None`;
- final recovery startup hook absent;
- no emergency recovery should normally be required.

The harness acceptance is based on **re-read Windows policy + recovery state**, not child-process `ExitCode` alone.

On full success it may remove the temporary `%LOCALAPPDATA%\WindowsNoSleep` runtime directory after copying evidence into ignored repository `artifacts/local-verification/...`.

## Failure behavior

If the main witness fails:

- do not run it a second time;
- do not manually repair power settings with `powercfg`;
- keep AC connected and lid open;
- the harness is allowed one automatic emergency call to the same production `-RecoveryOnly` path if a pending recovery snapshot remains;
- return all evidence, including final policy, final recovery status, and any remaining startup hook.

If exact restoration is not proven, STOP all further testing.

## Evidence to return to Control Tower

Return:

1. exact HEAD;
2. `git status --short` before and after;
3. complete terminal output;
4. `result.json`;
5. `before.json`;
6. `active.json`;
7. `after-crash.json`;
8. `after-recovery.json`;
9. relevant `events.log` tail;
10. whether endpoint security showed any prompt/block;
11. whether `%LOCALAPPDATA%\WindowsNoSleep` exists after successful completion (expected: absent);
12. whether `WindowsNoSleepRecovery` RunOnce exists after successful completion (expected: absent).

End report with:

`CONTROL_TOWER_READY`
