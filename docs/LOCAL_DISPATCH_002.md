# LOCAL DISPATCH 002 — BOUNDED APPLY / VERIFY / EXACT RESTORE SMOKE

Status: **AUTHORIZED — ONE TEMPORARY DC SLEEP-IDLE TRANSACTION ONLY**  
Date: 2026-09-14  
Control Tower issue: #1  
Implementation PR: #2  
Implementation branch: `feat/v1-portable-tray`  
Exact required implementation SHA: `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`

This dispatch follows a successful read-only Dispatch 001 probe on the owner's physical Windows 11 25H2 Modern Standby laptop.

Dispatch 001 evidence established:

- exact implementation SHA matched `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`;
- normal, non-elevated Windows PowerShell 5.1 + `Add-Type` were allowed by endpoint security;
- active scheme was Balanced `381b4222-f694-41f0-9685-ff5bb260df2e`;
- lid action was already `AC=0 / DC=0` (`Do Nothing`), therefore **no lid mutation is needed on this laptop**;
- sleep idle was `AC=0 / DC=1200 seconds`;
- Windows critical battery level was `5%`;
- Modern Standby S0 Low Power Idle was available, S3/hibernate/hybrid/fast-startup unavailable;
- `powercfg /requests` remained unavailable non-elevated with Access Denied;
- proposed policy plan contained exactly one item: `SleepIdle`, DC only, `1200 -> 0`;
- no mutation was attempted and the tracked worktree remained clean.

The purpose of Dispatch 002 is to prove that the real supported `powrprof.dll` write path can temporarily change that **single DC sleep-idle value**, verify it, and restore the exact original value immediately.

This is **not** a lid-close test, not a sleep test, not a battery-discharge test, and not a long soak.

---

## Required execution context

Use the same separate clean local verification checkout if it is still available.

Required conditions:

- exact detached SHA `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`;
- normal user session;
- **not elevated / not Run as Administrator**;
- laptop connected to AC for the entire dispatch;
- lid remains physically open;
- no intentional Sleep/Hibernate/Restart/Shutdown;
- do not change execution policy;
- do not disable/bypass SentinelOne, Defender, AppLocker, WDAC, or any other endpoint policy;
- do not edit source, commit, or push.

First prove:

```powershell
git rev-parse HEAD
```

It must print exactly:

`63ea8c99bd90b5416d00d6bec827a8b9e27b8218`

Otherwise STOP.

---

## Step 1 — mandatory fresh Probe immediately before mutation

Run:

```powershell
powershell.exe -NoProfile -File .\tools\LocalWindowsVerification.ps1 -Mode Probe
```

**Do not proceed to Step 2 unless the fresh probe still shows all of the following:**

- Active scheme = `381b4222-f694-41f0-9685-ff5bb260df2e`;
- Lid action = `AC=0`, `DC=0`;
- Sleep idle = `AC=0`, `DC=1200`;
- on AC;
- proposed changes = **exactly 1**;
- the only proposed change is:
  - `Name = SleepIdle`;
  - `ApplyAC = false`;
  - `ApplyDC = true`;
  - `OriginalAC = 0`;
  - `OriginalDC = 1200`;
  - `TargetAC = 0`;
  - `TargetDC = 0`;
- there is **no `LidAction` change**.

If any value differs, STOP and return the fresh Probe evidence. Do not run mutation mode.

---

## Step 2 — the only authorized mutation command

Only after Step 1 matches exactly, run:

```powershell
powershell.exe -NoProfile -File .\tools\LocalWindowsVerification.ps1 -Mode ApplyRestoreSmoke -AcknowledgeTemporaryPowerPolicyChange
```

Expected behavior of the harness:

1. re-read exact current state;
2. persist a write-ahead recovery snapshot **before** the first native write;
3. write only the active scheme's `SleepIdle` **DC** value from `1200` to `0`;
4. verify the temporary value;
5. hold for about 3 seconds;
6. restore DC `SleepIdle` to exactly `1200` in `finally` cleanup;
7. re-read and prove exact restore;
8. clear transaction recovery only after verified restore;
9. write `before.json`, `after.json`, and `result.json` under ignored `artifacts/local-verification/...`.

Success marker should include:

`LOCAL_WINDOWS_APPLY_RESTORE_SMOKE_COMPLETE`

and result outcome:

`APPLY_AND_EXACT_RESTORE_VERIFIED`

---

## Explicitly forbidden

Do **not**:

- manually run `powercfg /set*`, `/change`, `/hibernate`, `/setactive`, or any other power-setting mutation command;
- change lid action;
- change AC sleep timeout;
- change display timeout;
- change hibernate configuration or `hiberfil.sys`;
- change power-button or critical-battery action;
- switch the active power plan;
- edit registry power policy;
- close the laptop lid;
- unplug AC;
- intentionally enter Sleep/Modern Standby/Hibernate;
- restart or shut down Windows;
- run as Administrator;
- bypass endpoint security;
- edit or push code.

The only Windows policy mutation authorized is the harness's temporary `SleepIdle DC 1200 -> 0 -> 1200` transaction.

---

## Required evidence to return

Return to Control Tower:

1. exact `git rev-parse HEAD`;
2. fresh Step-1 Probe terminal summary and its proposed-change count;
3. complete ApplyRestoreSmoke terminal output;
4. ApplyRestoreSmoke `before.json`;
5. ApplyRestoreSmoke `after.json`;
6. ApplyRestoreSmoke `result.json`, especially:
   - `MutationAttempted`;
   - `MutationApplied`;
   - `RestoreAttempted`;
   - `RestoreVerified`;
   - `Outcome`;
   - `Error`;
   - `ProposedChanges`;
7. whether the transaction-local `recovery.json` still exists after successful completion (expected: no pending recovery remains);
8. `git status --short` after the test.

Expected final state on success:

- active scheme unchanged;
- lid remains `0/0`;
- SleepIdle returns exactly to `AC=0 / DC=1200`;
- no recovery snapshot remains pending;
- tracked git worktree remains clean.

---

## Stop / incident rules

If apply or restore reports any failure:

- **STOP immediately**;
- do not run the smoke a second time;
- do not manually 'fix' power settings;
- keep AC connected and lid open;
- return all evidence, especially any remaining transaction `recovery.json`, to Control Tower.

If exact restoration is not proven, no subsequent lid/Modern-Standby/battery testing is authorized.

If exact restoration is proven, Control Tower may separately authorize a later behavioral test. That later dispatch is not included here.
