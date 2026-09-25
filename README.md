# Windows No Sleep

Portable native Windows workload protection. The computer may stay awake while its display turns off. C# WinForms, .NET Framework 4.8, x64, non-elevated.

## Current development candidate

Version **0.4.7.0** bundles Battery Safety, normal shutdown/restart guard, recoverable lid/DC sleep/hibernate settings, screensaver and local inactivity protection, ARR/next-launch recovery and optional logon startup into the same `feat/v1-native-winforms` / DRAFT PR #4. On qualifying Modern Standby DC protection it also holds a transient DisplayRequired request; AC and other normal protection still allow display off.

The owner accepted focused physical gates for the exact 0.4.7.0 executable on the tested endpoint, including >600 seconds of Modern Standby DC idle without lock, AC request release and broker hard-kill restore. See [PROGRESS.md](PROGRESS.md) and [native acceptance](docs/NATIVE_V1_ACCEPTANCE.md) for scope and identity. Independent release review and a stable release decision remain pending.

## Update and run

Use the existing checkout. Exit the application from its tray menu, then run **`Update Windows No Sleep.cmd`** at the repository root. With no argument it selects GitHub's latest stable non-prerelease release. Since no stable release exists yet, use **`Update Windows No Sleep.cmd dev`** (or `--dev`) explicitly for the rolling `dev-latest` build. It checks the staged EXE against `SHA256SUMS.txt` before replacing the local build, then launches:

```text
artifacts\local-current\WindowsNoSleep.exe
```

No local build tools, new clone, new project directory or manual ZIP extraction is needed for each update. Click the tray icon for Settings. Close hides the Settings window; tray Exit releases protection and restores temporary settings. A duplicate launch shows one auto-closing five-second information window, not a second protection owner.

**Start with Windows** is available in Settings and defaults to OFF. It starts this executable after user sign-in, not before login. Keep the executable at the stable updater path after enabling it.

## Protection and limitations

- Inactivity sleep: direct SystemRequired request, with display-off permitted except for transient DisplayRequired on qualifying protected Modern Standby DC.
- Battery Safety: base 15%, respecting a higher readable Windows critical threshold plus five and critical status. Low/unknown DC battery status releases blockers and restores temporary settings; hysteresis or AC controls resume.
- Lid: temporary AC/DC Do Nothing only for supported laptops and permitted settings.
- Battery timeouts: temporary DC sleep/hibernate timeout protection, never global hibernation disable.
- Restart/shutdown: supported GUI block reason and session-end handling, **not** a guarantee against forced shutdown or every Windows Update deadline.
- Recovery: write-ahead journal, exact read-back restoration, ARR and recovery before a new protection session. A bounded elevated broker, used only after explicit UAC approval for the machine-inactivity override, restores that exact original and exits if the main app disappears. Other force-kill or power-loss restoration uses the next-launch journal; nothing can execute while power is absent.

The local Machine inactivity override writes the machine-wide `HKLM\...\InactivityTimeoutSecs` policy and affects every signed-in user/session. If Windows No Sleep ends without its elevated broker restoring the original value (for example, power loss, broker termination by security software, an unclean session end, or an elevated main app with no surviving broker), machine-wide inactivity auto-lock can remain disabled across reboot for all users. The recovery record is bound to the original account in `%LOCALAPPDATA%`; another account does not automatically repair it. The same account must relaunch Windows No Sleep and approve the one-shot administrator restore helper to restore the recorded original. Start with Windows defaults to OFF, so this recovery may not happen until that account launches the app. After an abnormal main-app exit, a very rare fast process-ID reuse can defer broker restoration until the unrelated process with that ID exits or the same account relaunches and restores.

Changing any protection option restarts Protection. While local machine-inactivity protection is requested, this can ask for administrator approval again, including after a previous UAC No.

The only writable power keys are LidAction AC/DC, SleepIdle DC and HibernateIdle DC. No display timeout, power button, critical battery action, replacement power scheme or Windows Update service is changed. Partial/blocked capabilities are visible rather than bypassed.

Runtime state and diagnostics are in `%LOCALAPPDATA%\WindowsNoSleep`. Pending/invalid recovery evidence is preserved. The application refuses new policy writes while restoration is unresolved. Do not delete recovery data to silence an error.

## Source and validation

- [Native runtime decision](docs/NATIVE_RUNTIME_DECISION.md): authoritative native architecture; supersedes old PowerShell packaging language.
- [V1 plan](docs/PLAN_V1.md): behavior and safety contracts.
- [Consolidated native acceptance](docs/NATIVE_V1_ACCEPTANCE.md): one final operator campaign rather than repeated per-feature downloads/tests.
- [Control Tower](docs/CONTROL_TOWER.md): project continuity.
- [Native operator README](native/README_NATIVE_PILOT.md): current binary behavior; filename retained for packaging compatibility.

CI compiles the Windows SDK ABI assertions, the native Release build and deterministic fake-provider tests, plus a real non-mutating PowerRequest self-test. The separate stable-tag workflow repeats those gates and checks tag, current main and version identity before publication; no stable tag or release exists yet. Owner physical evidence applies to the tested endpoint and exact accepted EXE only. The unsigned package is not universally EDR certified; Issue #3 remains open.

The old PowerShell PR #2 and Dispatch 004 are superseded/reference-only. Do not run the quarantined PowerShell integration path. `legacy/` and local ScreenSaverDisabler material are historical references, not the current application.
