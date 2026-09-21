# PROGRESS

## Current native implementation — 2026-09-21

Active lane: `feat/v1-native-winforms`, SAME DRAFT PR #4. Version 0.4.0.0 is the bundled native V1 development candidate. No merge/release-candidate acceptance is implied.

Owner explicitly requested all seven remaining features in one update, with manual testing consolidated at the end. Durable instruction: Issue #1 comment **5754988623**. The existing updater path remains `artifacts\local-current\WindowsNoSleep.exe`; no new clone or directory reorganization.

### Implemented together

- Direct SystemRequired request, with display-off still allowed.
- Native shutdown reason window and session-end handling; normal requests may be blocked, critical/forced shutdown and logoff are allowed.
- Battery monitor and safety controller: 15% base or higher readable Windows critical threshold +5, critical/unknown DC safety pause, hysteresis and safe AC resume.
- Four-key native policy allowlist: LidAction AC/DC, SleepIdle DC, HibernateIdle DC. Hibernate timeout is included only when hibernation is present. No unrelated setting writes.
- Durable versioned recovery storage; attempted-before-write ordering; rollback after partial failures; exact read-back restore before clearing pending recovery; next-launch recovery before new policy writes; external conflicts and invalid journals preserved.
- ARR callback/restart registration, bounded crash-recovery lock attempt and Windows cancellation pings. Force-kill/power-loss recovery remains next-launch, not an instantaneous guarantee.
- Opt-in Start with Windows checkbox (default OFF), owning one quoted direct-EXE HKCU Run value.
- Settings/status for all capabilities, distinct tray state badges, diagnostics, bounded local logs and a last-restore receipt.
- Single-instance mutex acquisition corrected to use actual ownership, with the existing five-second duplicate notice retained.

### Automated validation

`SelfTests.cs` covers fake-provider battery thresholds, controller lifecycle, policy write-ahead ordering, crash boundaries, rollback failures, conflict preservation, corrupt/foreign journals, settings, mutex ownership and startup command quoting. It does not create production startup entries or mutate live power settings. `native/tests/AbiCheck.cpp` validates capability offsets against the Windows SDK.

The Actions workflow builds Release x64, runs those tests plus a real non-mutating PowerRequest self-test, records SHA-256/build ID and publishes the compatible five `dev-latest` assets only after success. Consult the exact-head Actions run and Issue #1 completion comment for actual outcomes; this source commit does not predeclare CI green.

### Evidence already reported by the owner

In the current conversation, screenshots show the native application/branding and countdown duplicate notice. The owner explicitly reports Start -> Protected -> Exit with window/tray/process cleanup working for the earlier native UI build. The updater was pulled locally and the resulting app opened.

Those reports do not prove the new policy/ARR/battery/lid/restart/autostart paths. No unseen hash, endpoint-security product detail, closed-lid, DC, overnight or forced-crash result is invented.

### Next operator action

Once the complete candidate's exact-head CI/release is verified, Exit the old app and double-click the SAME `Update Windows No Sleep.cmd`. Open Settings from the tray. One consolidated final acceptance campaign is in `docs/NATIVE_V1_ACCEPTANCE.md`; no per-feature ZIP loop.

Final native physical labels (`LID_VERIFIED`, `BATTERY_VERIFIED`, `HEADLESS_VERIFIED`, final `EDR_VERIFIED`) remain PENDING. Forced Windows actions, thermal protection and power loss are not defeated. A restore failure requires recovery attention, not more mutation tests.

## Historical reference — superseded paths

- Old PowerShell PR #2 is CLOSED/superseded. Old Dispatch 004 remains HOLD/cancelled and must not be run.
- Issue #3 recorded security quarantine involving the earlier PowerShell runtime/recovery path; the exact triggering heuristic was not established. No exclusion, policy bypass or renamed/packed workaround is authorized.
- Earlier PowerShell physical evidence (read-only baseline, DC SleepIdle 1200 -> 0 -> 1200, AC lid closed with an external monitor) informs the native port but does not certify it.
- The original 18-section native-pilot handoff on main described the earlier pending pilot. Its pilot-only sequencing is superseded for this source implementation by the current explicit owner bundle request, not by an invented PASS.
- GitHub remains source of truth. Issue #3 stays open until current native endpoint/recovery acceptance is actually evidenced.
