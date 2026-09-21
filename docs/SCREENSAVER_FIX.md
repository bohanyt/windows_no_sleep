# Screensaver / idle-lock correction — 2026-09-21

Owner direction is recorded in Issue #1 comment 5755803509. This is a primary requirement, not a cosmetic follow-up. Version 0.4 lacked screensaver inhibition; SystemRequired alone did not satisfy it. A password/lock screen while the app says Protected is NOT a passing idle-lock test.

## Version 0.4.1 implementation

`Prevent screensaver and its automatic sign-in prompt` defaults ON for both new installs and existing 0.4 settings. A missing nullable setting means ON; an explicit false persists. Corrupt options do not authorize new screensaver changes.

The native app reads the ordinary session screensaver active flag, timeout and password-on-resume state. When permitted, it writes a recovery record BEFORE `SystemParametersInfoW(SPI_SETSCREENSAVEACTIVE, FALSE, NULL, 0)`, then verifies disabled state. fWinIni=0 means the user profile is not modified. Password-on-resume itself, timeout, selected saver, account passwords and enforced lock policies are NOT disabled.

Stop, Exit, Battery Safety and suspend restore the exact prior active flag with readback. Crash/next-launch recovery uses `desktop-recovery.json`, independently from the power journal. A restore error in one domain does not skip the other. A logon AuthenticationId distinguishes session-only state from a later login: after a new login, no stale volatile setting is replayed into the fresh session. Profile conflicts and corrupt/foreign journals are preserved instead of guessed or deleted. Restoration receipts are stored locally.

No SendInput, mouse jiggling, fake keys, repeated policy writes, auto-unlock, elevated task/service or EDR bypass is used. DisplayRequired is NOT represented as a screensaver blocker. The display may still turn off; preventing ordinary screensaver activation does not promise to defeat every Windows lock source.

## Truthful limits

Known screensaver policy, machine inactivity timeout, MDM DeviceLock timeout and Dynamic Lock settings are inspected read-only. Detected limitations make the main status Degraded rather than pretending all idle-lock paths are prevented. Session-lock observations are logged and surfaced; the app does not pretend it can tell a manual Win+L from every OS/third-party lock cause. Presence sensing, third-party security software and manual/forced lock remain outside the supported inhibition contract. A zero-warning scan is not an exhaustive policy inventory.

## Distribution and acceptance

Same branch / DRAFT PR #4 and SAME `Update Windows No Sleep.cmd`; executable remains `artifacts\local-current\WindowsNoSleep.exe`. No manual ZIP loop. Publish only after exact-head CI passes. Do not call this stable or physically verified solely because automated tests pass.

One focused acceptance witness supersedes repeating earlier lid tests: unlock/sign in normally, plug in, Exit old build, run the existing updater, open Settings, confirm version/build in Diagnostics and screensaver checkbox ON. Verify the screensaver status says Active with no lock-policy warning. Leave the laptop untouched longer than the timeout that previously locked it (timeout is recorded in the local SCREENSAVER_ACTIVE log). Do not use video playback/mouse activity to mask idle behavior. Return and check that no password prompt occurred; inspect SESSION_LOCK_OBSERVED and heartbeat continuity. Stop Protection must restore the original screensaver value and log SCREENSAVER_RESTORE_VERIFIED when an original enabled value was changed. A policy warning or unexpected lock means acceptance remains blocked; do not weaken endpoint security or rerun restart/crash tests to work around it.

Primary contracts:
- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow
- https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-controlpaneldisplay
- https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-token_statistics
- https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-gettokeninformation

Automated coverage uses fake APIs: write-before-disable, original disabled state, failed/ignored writes, restore and receipt failures, crash/relaunch, fresh-logon behavior, invalid/foreign/conflicting journals, settings migration, policy refusal, live-lock warnings, controller Stop/Battery Safety/suspend/crash integration. These are regression evidence, not endpoint idle-time proof.
