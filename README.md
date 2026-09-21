# Windows No Sleep

Portable native Windows workload protection. The computer may stay awake while its display turns off. C# WinForms, .NET Framework 4.8, x64, non-elevated.

## Current development candidate

Version **0.4.0.0** bundles Battery Safety, normal shutdown/restart guard, recoverable lid/DC sleep/hibernate settings, ARR/next-launch recovery and optional logon startup into the same `feat/v1-native-winforms` / DRAFT PR #4.

This is implemented development code. Hosted automated tests and final physical endpoint acceptance are separate. See [PROGRESS.md](PROGRESS.md) and the exact-head Actions run for evidence; do not treat this README as a physical PASS.

## Update and run

Use the existing checkout. Exit the application from its tray menu, then double-click **`Update Windows No Sleep.cmd`** at the repository root. The updater retrieves the completed GitHub `dev-latest` build and launches:

```text
artifacts\local-current\WindowsNoSleep.exe
```

No local build tools, new clone, new project directory or manual ZIP extraction is needed for each update. Click the tray icon for Settings. Close hides the Settings window; tray Exit releases protection and restores temporary settings. A duplicate launch shows one auto-closing five-second information window, not a second protection owner.

**Start with Windows** is available in Settings and defaults to OFF. It starts this executable after user sign-in, not before login. Keep the executable at the stable updater path after enabling it.

## Protection and limitations

- Inactivity sleep: direct SystemRequired request, with display-off permitted.
- Battery Safety: base 15%, respecting a higher readable Windows critical threshold plus five and critical status. Low/unknown DC battery status releases blockers and restores temporary settings; hysteresis or AC controls resume.
- Lid: temporary AC/DC Do Nothing only for supported laptops and permitted settings.
- Battery timeouts: temporary DC sleep/hibernate timeout protection, never global hibernation disable.
- Restart/shutdown: supported GUI block reason and session-end handling, **not** a guarantee against forced shutdown or every Windows Update deadline.
- Recovery: write-ahead journal, exact read-back restoration, ARR and recovery before a new protection session. Power-loss/force-kill recovery runs at the next launch; nothing can execute while power is absent.

The only writable power keys are LidAction AC/DC, SleepIdle DC and HibernateIdle DC. No display timeout, power button, critical battery action, replacement power scheme or Windows Update service is changed. Partial/blocked capabilities are visible rather than bypassed.

Runtime state and diagnostics are in `%LOCALAPPDATA%\WindowsNoSleep`. Pending/invalid recovery evidence is preserved. The application refuses new policy writes while restoration is unresolved. Do not delete recovery data to silence an error.

## Source and validation

- [Native runtime decision](docs/NATIVE_RUNTIME_DECISION.md): authoritative native architecture; supersedes old PowerShell packaging language.
- [V1 plan](docs/PLAN_V1.md): behavior and safety contracts.
- [Consolidated native acceptance](docs/NATIVE_V1_ACCEPTANCE.md): one final operator campaign rather than repeated per-feature downloads/tests.
- [Control Tower](docs/CONTROL_TOWER.md): project continuity.
- [Native operator README](native/README_NATIVE_PILOT.md): current binary behavior; filename retained for packaging compatibility.

CI compiles the Windows SDK ABI assertions, the native Release build and deterministic fake-provider tests, plus a real non-mutating PowerRequest self-test. Physical lid/DC/overnight, sign-in startup and final protected-endpoint acceptance remain separately evidenced.

The old PowerShell PR #2 and Dispatch 004 are superseded/reference-only. Do not run the quarantined PowerShell integration path. `legacy/` and local ScreenSaverDisabler material are historical references, not the current application.
