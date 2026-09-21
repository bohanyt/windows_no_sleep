# PROGRESS

## Current correction — 2026-09-21: screensaver / idle lock

SAME `feat/v1-native-winforms` / DRAFT PR #4. Version 0.4.1.0 adds the missing primary screensaver capability. Owner direction/active scope: Issue #1 comment **5755803509**. Previous 0.4 `Protected` status did not mean autolock/screensaver was inhibited; the owner's password-screen report is a real acceptance failure.

Implemented: default-on session-only screensaver suppression with write-ahead recovery and readback; exact Stop/Exit/Battery Safety/suspend restoration; same-logon crash recovery; new-logon expiry without replaying stale volatile values; independent power/screensaver recovery attempts; backward-compatible setting; read-only lock-policy diagnostics; visible Degraded status on detected policy limits or lock observation. No password, secure-sign-in, manual-lock or enterprise-policy bypass.

See `docs/SCREENSAVER_FIX.md` for the bounded mechanism, limits and one focused idle acceptance witness. Automated regressions run with fake desktop APIs alongside the full previous native suite before dev-latest publication. This source record does NOT predeclare the new CI result or endpoint PASS. Exact candidate SHA/CI/publication will be reported in Issue #1.

Delivery unchanged: Exit old app -> double-click the EXISTING `Update Windows No Sleep.cmd` -> `artifacts\local-current\WindowsNoSleep.exe`. No new folder, clone, Git pull or ZIP is needed for the binary. Stable release remains blocked until the actual idle-lock failure and remaining acceptance requirements are resolved.

Owner additionally reported AC lid clamshell behavior (internal panel off, HDMI primary) and DC lid behavior working. These are owner-reported observations, not independent timeout/overnight proof. No new restart-guard, crash-recovery or autostart PASS is inferred. Screensaver/lock-free physical acceptance is PENDING.

## Bundled native 0.4 implementation — historical baseline

Owner requested all seven remaining features in one update, with manual testing consolidated at the end (Issue #1 **5754988623**). Candidate `4788830815b95b3d41ead67d9adfd9ddf8d0965a` was published as dev-latest after hosted tests. No merge or stable acceptance was implied.

- Direct SystemRequired request, with display-off allowed.
- Native shutdown reason window and session-end handling; normal requests may be blocked, critical/forced shutdown and logoff allowed.
- Battery monitor: 15% base or readable critical threshold +5, critical/unknown DC pause, hysteresis and safe AC resume.
- Four-key power allowlist: LidAction AC/DC, SleepIdle DC, HibernateIdle DC when hibernation is present.
- Durable power journal, attempted-before-write ordering, partial rollback, exact readback restore and restore-before-protect; conflicting/invalid journals preserved.
- ARR callback/restart registration; force-kill/power-loss recovery is next-launch, not instantaneous.
- Opt-in Start with Windows (default OFF), one quoted direct-EXE HKCU Run value.
- Capability UI, tray badges, diagnostics, bounded logs, restoration receipt, single owner and five-second duplicate notice.

`SelfTests.cs` contains fake-provider battery/controller/policy/storage/ownership tests. `native/tests/AbiCheck.cpp` validates Windows SDK capability offsets. Actions builds Release x64, runs these regressions and a real non-mutating power request self-test, records SHA-256/build ID and publishes the five compatible dev-latest assets only after success.

Earlier owner screenshots/reports established native app/branding, duplicate notice, updater launch and Start/Stop/Exit UI behavior. These are not full native policy/ARR/restart/autostart/overnight acceptance. Final labels remain pending where not actually evidenced.

## Historical reference — superseded paths

- Old PowerShell PR #2 is CLOSED/superseded. Old Dispatch 004 remains HOLD/cancelled and must not run.
- Issue #3 recorded security quarantine involving the earlier PowerShell runtime/recovery path; exact heuristic unconfirmed. No exclusion, policy bypass or repacking workaround is authorized.
- Earlier PowerShell read-only baseline, DC SleepIdle 1200 -> 0 -> 1200, and AC lid/external-monitor evidence informs but does not certify the native port.
- The original 18-section pilot handoff on main described the earlier pending pilot. Its sequencing was superseded for implementation by the explicit bundle request, not an invented physical PASS.
- GitHub remains source of truth. Issue #3 remains open pending current native endpoint/recovery acceptance.
