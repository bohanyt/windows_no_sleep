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

Next engineering step is to redesign or repackage the recovery/runtime path so the exact-restore safety contract remains intact. Candidate directions must be evaluated against Issue #3 and the original owner preference for portable/simple deployment; do not weaken recovery safety just to reduce detections.

### Issue #3 remediation proposal — owner approval pending

Durable proposal: `docs/ISSUE_003_EDR_PLAN.md` on `main`.

Status: **PROPOSED, not implementation or local-execution authority**.

Recommended direction:

- conventional portable C# WinForms / .NET Framework 4.8 executable, with no PowerShell runtime wrapper;
- a small non-mutating compiled pilot before porting all features;
- trusted release signing/provenance as a target, not a claim of an available certificate or guaranteed antivirus acceptance;
- preserve exact recovery and validate one transparent, documented direct-EXE recovery mechanism before enabling real lid/DC mutations;
- do not treat removal of RunOnce, a different extension or a new startup mechanism as a proven fix;
- preserve final V1 goals; the non-mutating pilot is not approval to silently drop lid/DC requirements;
- one implementation lane; no swarm.

Additional source-level safety finding at `8059f92f51702c35646e94c8b1afe1e1e3c96934`:

- `tests/WindowsIntegrationTests.ps1` launches the real app with default settings, force-kills it, and unconditionally deletes its temporary runtime directory;
- it does not prevent laptop policy writes before launch or verify policy restoration before deleting possible recovery data;
- hosted no-battery CI success therefore does not establish that this test is non-mutating on a laptop;
- this is a reviewed upstream safety risk, not a claim that the reporter's machine definitely retained changed settings.

Next bounded actions after owner review:

1. obtain existing EDR alert details, exact tested contributor SHA and approved read-only current Windows/recovery state; do not reproduce the quarantine;
2. harden test isolation and recovery-data preservation before new real-policy testing;
3. if approved, build the small compiled pilot and validate its exact artifact before the rest of the port;
4. independently review recovery/sign-in semantics and reauthorize physical tests only through a new exact-SHA dispatch.

No implementation source was changed for this proposal. Local Cursor remains **HOLD / no new dispatch**. No certificate purchase, security exclusion, endpoint script execution or new policy mutation is authorized by the proposal.

### Previously verified physical evidence

- `LOCAL_READ_ONLY_VERIFIED` — physical Windows 11 25H2 / Modern Standby S0 baseline read successfully.
- `LOCAL_POLICY_TRANSACTION_VERIFIED` — real `SleepIdle DC 1200 -> 0 -> 1200` exact restore passed.
- `LID_CLOSED_AC_EXTERNAL_DISPLAY_VERIFIED` — lid closed on AC for ~90s with external monitor connected; workload heartbeat continued with max gap ~1.046s.

These passes remain evidence for their original tested builds, not automatic verification of a future compiled port.

### Still open

- Issue #3 EDR compatibility/root-cause redesign;
- affected-endpoint policy/recovery reconciliation if necessary;
- hosted-test mutation/cleanup hazard;
- owner approval of the proposed compiled packaging;
- production crash-recovery lifecycle after redesign;
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
