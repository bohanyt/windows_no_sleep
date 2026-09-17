# PROGRESS

## Current status — 2026-09-17

Phase: **P2 — physical Windows integration / EDR compatibility blocker**.

GitHub is the source of truth. DRAFT PR #2 remains the implementation lane on `feat/v1-portable-tray` at head `8059f92f51702c35646e94c8b1afe1e1e3c96934` unless GitHub moves it.

### New blocking evidence — Issue #3

Issue #3 (`EDR quarantines PowerShell launcher/recovery path during Windows integration test`) was opened on 2026-09-17 from a protected Windows endpoint.

Observed report:

- running `powershell.exe -NoProfile -File .\tests\WindowsIntegrationTests.ps1` against the current implementation family triggered endpoint-security/EDR quarantine;
- quarantined/removed items included the main `WindowsNoSleep.ps1`, launcher, modules, tests and local-verification scripts;
- the security UI also quarantined the per-user `WindowsNoSleepRecovery` RunOnce registry value associated with `powershell.exe (Interactive Session)`;
- no AV/EDR bypass, exclusion or allowlist was used;
- no deletion was committed; the contributor restored the local worktree with `git restore .`.

The issue explicitly notes that the combination of PowerShell execution, hidden recovery invocation, and RunOnce persistence may be contributing to the heuristic, but this is an observation rather than a proven root cause.

Evidence label: **`EDR_COMPATIBILITY_FAILED_ON_REPORTED_ENDPOINT`**.

### Control Tower decision

**Dispatch 004 is now HOLD, not executable, until Issue #3 is triaged.**

Reason: Dispatch 004 exercises the production PowerShell + recovery persistence path on a protected endpoint. Re-running it before redesign/triage could simply reproduce the quarantine and is unnecessary.

Do not:

- disable or bypass EDR/Defender/SentinelOne;
- add unsafe exclusions merely to make the test pass;
- rerun the quarantined path on the affected endpoint;
- claim release-package/EDR compatibility.

Next engineering step is to redesign or repackage the recovery/runtime path so the exact-restore safety contract remains intact without relying on an EDR-hostile combination. Candidate directions must be evaluated against Issue #3 and the original owner preference for portable/simple deployment; do not weaken recovery safety just to reduce detections.

### Previously verified physical evidence

- `LOCAL_READ_ONLY_VERIFIED` — physical Windows 11 25H2 / Modern Standby S0 baseline read successfully.
- `LOCAL_POLICY_TRANSACTION_VERIFIED` — real `SleepIdle DC 1200 -> 0 -> 1200` exact restore passed.
- `LID_CLOSED_AC_EXTERNAL_DISPLAY_VERIFIED` — lid closed on AC for ~90s with external monitor connected; workload heartbeat continued with max gap ~1.046s.

### Still open

- Issue #3 EDR compatibility/root-cause redesign;
- production crash-recovery lifecycle after EDR-safe redesign;
- clean Stop/Exit exact restore witness;
- `BATTERY_VERIFIED`;
- `HEADLESS_VERIFIED`;
- longer Modern Standby/overnight soak;
- final protected-endpoint package acceptance;
- independent release review before PR #2 is ready/merged.

---

## Historical status — 2026-09-14

Phase: **P2 — physical Windows integration / production recovery gate**.

The 2026-09-14 state below is historical and superseded by the 2026-09-17 EDR blocker above.

- Frozen implementation/test head for the next local gate was `8059f92f51702c35646e94c8b1afe1e1e3c96934`.
- Production tray runtime had transactional temporary LidAction/DC SleepIdle protection, exact restore, startup recovery, active-plan drift handling, and `-RecoveryOnly`.
- Hosted Windows PowerShell 5.1 CI was green for static/core, read-only power-policy, transaction/recovery, runtime-policy lifecycle, and hosted tray E2E.
- Dispatch 001 PASS: read-only physical baseline.
- Dispatch 002 PASS: direct real apply/restore smoke.
- Dispatch 003 PASS: AC closed-lid workload witness with external display connected.
- Dispatch 004 was prepared but is now HOLD due to Issue #3.
