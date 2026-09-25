# Windows No Sleep 0.4.7 — native V1 development build

Keeps computer workloads running. On Modern Standby laptops while protected on battery, it also keeps the display logically on to prevent display-idle Modern Standby entry. Portable x64 C# WinForms application for .NET Framework 4.8, running as the current user. The owner accepted focused physical gates for the exact 0.4.7.0 candidate on one endpoint; independent review and stable release remain pending. The unsigned build is not universally EDR certified.

## Use the existing updater

Exit Windows No Sleep through its tray menu, then run `Update Windows No Sleep.cmd dev` in your existing repository folder while stable publication is pending. The default updater channel is latest stable non-prerelease and does not fall back to dev. It verifies the staged EXE against `SHA256SUMS.txt` before replacing `artifacts\local-current\WindowsNoSleep.exe`. No new clone, folder reorganization or manual ZIP extraction is required.

A first launch starts protection in the tray. Click the tray icon for Settings. An accidental second launch shows the existing 5-second notice without another protection owner. Close hides Settings; tray **Exit** quits and attempts verified restoration.

## Included features

- Direct SystemRequired awake request. On Modern Standby hardware with a battery, a separate transient DisplayRequired request is active only while battery protection is running on DC outside Battery Safety. It is released on AC, Stop, Suspend and cleanup. This can increase battery use with the lid open; closing the lid can still darken the physical panel.
- Normal shutdown/restart guard with a visible Windows block reason. Forced/critical shutdown and logoff are not vetoed. This does not disable or guarantee prevention of every Windows Update restart.
- Battery Safety: 15% base threshold, or higher when a readable Windows critical threshold plus five requires it. Unknown/critical DC battery status releases protection. A five-point hysteresis prevents rapid resume/pause cycling; AC permits resumption unless an unresolved recovery error exists.
- Temporary lid AC/DC Do Nothing where the device has a lid and Windows permissions allow it.
- Temporary DC SleepIdle Never, and HibernateIdle Never when hibernation is present. No AC sleep/display values, power-button actions, critical-battery actions, update services, or global hibernation feature settings are changed.
- Versioned, atomically written recovery journal before each attempted power-setting write. Stop/Exit restores recorded originals and reads them back before clearing the journal.
- ARR crash/hang recovery registration plus restore-before-protect on every normal launch. ARR is best effort. After explicit UAC for the machine-inactivity override, a bounded elevated broker restores its exact original and exits if the main process disappears. Other settings after power loss, hard termination or EDR termination rely on the next-launch journal. Pending/corrupt/foreign/conflicting journals are preserved, not guessed or erased.
- Optional **Start with Windows (after I sign in)**. Default OFF. The checkbox owns only the `WindowsNoSleep.Native` value under the current user's Run key and directly launches this EXE. No service, task, RunOnce or script recovery process.
- Local diagnostics, state-specific tray badges, bounded event logging and a restoration receipt.
- Session screensaver suppression and local inactivity protection where permitted; the machine-inactivity path uses explicit UAC for the bounded broker.

The local Machine inactivity override writes the machine-wide `HKLM\...\InactivityTimeoutSecs` policy and affects every signed-in user/session. If Windows No Sleep ends without its elevated broker restoring the original value (for example, power loss, broker termination by security software, an unclean session end, or an elevated main app with no surviving broker), machine-wide inactivity auto-lock can remain disabled across reboot for all users. The recovery record is bound to the original account in `%LOCALAPPDATA%`; another account does not automatically repair it. The same account must relaunch Windows No Sleep and approve the one-shot administrator restore helper to restore the recorded original. Start with Windows defaults to OFF, so this recovery may not happen until that account launches the app. After an abnormal main-app exit, a very rare fast process-ID reuse can defer broker restoration until the unrelated process with that ID exits or the same account relaunches and restores.

Changing any protection option restarts Protection. While local machine-inactivity protection is requested, this can ask for administrator approval again, including after a previous UAC No.

## Safety and data

Runtime data is under `%LOCALAPPDATA%\WindowsNoSleep`: `settings.json`, pending `recovery.json`, `last-restore.json`, `events.log` and an ownership lock. The updater does not delete this data.

Do not delete a pending recovery journal or change the power plan while validating apply/restore. External setting conflicts cause a safety stop and a retained journal; the app will not overwrite another actor's setting silently. If policy/permissions/ARR ownership prevent safe changes, Settings reports partial/degraded capability while retaining basic awake protection where safe.

Windows security remains enabled. Stop on a security detection; no exclusion, quarantine release, forced rerun or elevation workaround. Explicit UAC for the supported machine-inactivity operation is part of the normal feature. The old PowerShell Dispatch 004 remains prohibited. Physical closed-lid use must maintain cooling and normal critical-battery/thermal protection.

## Development evidence

CI compiles the exact native EXE, checks managed ABI offsets against the Windows SDK, runs the real non-mutating power-request self-test, and runs fake-provider battery/transaction/controller/storage/ownership regression tests before publishing `dev-latest`.

`BUILD_SHA.txt` identifies the source build; `SHA256SUMS.txt` records its EXE SHA-256. The owner's accepted 0.4.7.0 physical candidate had SHA-256 `7a62745e408792a0c1c3d4e863e0f46a3af7fc9c18e53b567d0be87fbd397e74`. CI after packaging/docs reconciliation must prove byte identity before inheriting those physical observations. Automatic tests and one endpoint do not establish universal EDR or overnight acceptance. See `docs/NATIVE_V1_ACCEPTANCE.md` and `PROGRESS.md` in the repository.
