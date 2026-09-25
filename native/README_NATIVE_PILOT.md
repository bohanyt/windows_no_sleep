# Windows No Sleep 0.4.7 — native V1 development build

Keeps computer workloads running. On Modern Standby laptops while protected on battery, it also keeps the display logically on to prevent display-idle Modern Standby entry. Portable x64 C# WinForms application for .NET Framework 4.8, running as the current user. This is a bundled development candidate, not a claim of final physical-laptop/EDR/overnight acceptance.

## Use the existing updater

Exit Windows No Sleep through its tray menu, then double-click `Update Windows No Sleep.cmd` in your existing repository folder. It downloads the CI-built executable, rather than compiling on your laptop. The executable stays at `artifacts\local-current\WindowsNoSleep.exe`. No new clone, folder reorganization or manual ZIP extraction is required.

A first launch starts protection in the tray. Click the tray icon for Settings. An accidental second launch shows the existing 5-second notice without another protection owner. Close hides Settings; tray **Exit** quits and attempts verified restoration.

## Included features

- Direct SystemRequired awake request. On Modern Standby hardware with a battery, a separate transient DisplayRequired request is active only while battery protection is running on DC outside Battery Safety. It is released on AC, Stop, Suspend and cleanup. This can increase battery use with the lid open; closing the lid can still darken the physical panel.
- Normal shutdown/restart guard with a visible Windows block reason. Forced/critical shutdown and logoff are not vetoed. This does not disable or guarantee prevention of every Windows Update restart.
- Battery Safety: 15% base threshold, or higher when a readable Windows critical threshold plus five requires it. Unknown/critical DC battery status releases protection. A five-point hysteresis prevents rapid resume/pause cycling; AC permits resumption unless an unresolved recovery error exists.
- Temporary lid AC/DC Do Nothing where the device has a lid and Windows permissions allow it.
- Temporary DC SleepIdle Never, and HibernateIdle Never when hibernation is present. No AC sleep/display values, power-button actions, critical-battery actions, update services, or global hibernation feature settings are changed.
- Versioned, atomically written recovery journal before each attempted power-setting write. Stop/Exit restores recorded originals and reads them back before clearing the journal.
- ARR crash/hang recovery registration plus restore-before-protect on every normal launch. ARR is best effort. After power loss, hard termination or EDR termination, exact recorded settings can be restored only when the application runs again. Pending/corrupt/foreign/conflicting journals are preserved, not guessed or erased.
- Optional **Start with Windows (after I sign in)**. Default OFF. The checkbox owns only the `WindowsNoSleep.Native` value under the current user's Run key and directly launches this EXE. No service, task, RunOnce or script recovery process.
- Local diagnostics, state-specific tray badges, bounded event logging and a restoration receipt.

## Safety and data

Runtime data is under `%LOCALAPPDATA%\WindowsNoSleep`: `settings.json`, pending `recovery.json`, `last-restore.json`, `events.log` and an ownership lock. The updater does not delete this data.

Do not delete a pending recovery journal or change the power plan while validating apply/restore. External setting conflicts cause a safety stop and a retained journal; the app will not overwrite another actor's setting silently. If policy/permissions/ARR ownership prevent safe changes, Settings reports partial/degraded capability while retaining basic awake protection where safe.

Windows security remains enabled. Stop on a security detection; no exclusion, quarantine release, forced rerun or elevation workaround. Physical closed-lid use must maintain cooling and normal critical-battery/thermal protection.

## Development evidence

CI compiles the exact native EXE, checks managed ABI offsets against the Windows SDK, runs the real non-mutating power-request self-test, and runs fake-provider battery/transaction/controller/storage/ownership regression tests before publishing `dev-latest`.

`BUILD_SHA.txt` identifies the source build; `SHA256SUMS.txt` records its EXE SHA-256. Automatic tests do not establish physical lid/DC/overnight behavior, login-startup behavior or universal EDR acceptance. The consolidated final operator campaign is documented in `docs/NATIVE_V1_ACCEPTANCE.md` in the repository.
