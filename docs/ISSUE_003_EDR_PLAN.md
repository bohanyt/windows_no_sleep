# Issue #3 — EDR compatibility remediation plan

Status: **PROPOSED — owner review required; NOT a coding or local-test dispatch**  
Date: 2026-09-17  
Coordination: Issue #1  
Incident: Issue #3  
Existing implementation: DRAFT PR #2 / `feat/v1-portable-tray`  
Source reviewed: `8059f92f51702c35646e94c8b1afe1e1e3c96934`

Dispatch 004 remains **HOLD**. This document does not lift that hold or supersede the approved product defaults in `PLAN_V1.md`. In particular, a non-mutating pilot described below is not acceptance of a reduced-feature final product.

## 1. Recommendation and size

Recommend a conventional compiled, portable C# WinForms application targeting .NET Framework 4.8, with direct Windows API calls and a verifiable release/signing pipeline. Do not package the existing PowerShell inside an EXE wrapper.

This is a bounded runtime-host migration plus recovery/test hardening, not a new product architecture. The PowerShell host/controller/UI will need substantial porting; the Windows API contracts, product decisions, test scenarios and lessons from the original implementation remain useful. Existing physical passes belong to their tested builds and do NOT automatically certify the new binary.

Keep one implementation lane and one implementation owner, with an independent safety review before enabling real policy writes. No swarm. No simultaneous laptop power-policy tests.

Owner decision requested: approve conventional portable EXE distribution instead of insisting on a non-EXE launcher. Trusted signing identity and any associated purchasing decision are separate prerequisites; this proposal does not claim a signing certificate is already available.

## 2. Evidence, hypotheses and missing information

### Reported in Issue #3

The reporter ran `tests/WindowsIntegrationTests.ps1` through PowerShell on a protected Windows endpoint. Multiple project files and the `WindowsNoSleepRecovery` registry entry were quarantined. No security bypass/exclusion was used. The reporter restored tracked files using `git restore .` and did not rerun the test.

This is a reported protected-endpoint compatibility failure, not proof that the software is malware and not a vendor-confirmed false-positive determination. It is also not a Dispatch 004 PASS/FAIL report. The exact contributor commit and endpoint configuration have not been supplied in the issue body. Do not assume the reporting endpoint has the same power-policy baseline as the earlier owner laptop.

### Confirmed in upstream source

At the reviewed SHA, `WindowsNoSleep.ps1`:

- runs the tray app through Windows PowerShell;
- registers `WindowsNoSleepRecovery` under per-user RunOnce;
- invokes PowerShell with `-WindowStyle Hidden` and `-RecoveryOnly` in that entry;
- registers recovery based on battery/settings before the actual transaction result is known;
- calls the real temporary-policy lifecycle from the production app.

### Not established

The issue does not identify the first detection event, engine/rule, exact process tree, agent/policy version, or vendor verdict. PowerShell, dynamic interop compilation, startup registration, test process termination and associated behavioral context are candidates to investigate, not individually proven causes. Several files being quarantined does not prove each file independently triggered a detection.

Obtain existing security-console evidence through the endpoint administrator rather than reproducing the quarantine: exact commit/package hashes, OS build, EDR product/agent version, alert ID/time, classification, process/command lineage and affected objects. Redact usernames, hostnames and organization identifiers from public GitHub material. Do not upload organization logs or samples externally without authorization.

## 3. Safety finding: the old hosted E2E is not a safe generic laptop test

Reviewed `tests/WindowsIntegrationTests.ps1` launches the real app with default settings, force-kills it, and unconditionally deletes its temporary LOCALAPPDATA directory in `finally`. It does not prevent the production app from applying laptop policy changes and does not perform a verified policy restore before deleting that directory.

The hosted no-battery runner passing this test is therefore not evidence that the same command is non-mutating on a battery-equipped endpoint. Combined with the current production behavior, this creates a source-level risk of deleting a recovery snapshot after a real temporary policy write. This review does NOT establish that this sequence occurred on the reporter's machine; that requires endpoint evidence.

Immediate triage must establish the affected endpoint's current active scheme, relevant AC/DC values, pending recovery data and recovery startup registration using approved read-only OS/IT observation. Do not execute quarantined project scripts, delete journals, clear startup entries or guess original values. `git restore .` restores repository files, not Windows power-policy state. Preserve available originals before any separately authorized recovery action.

The first source-hardening work, after approval, must separate hosted non-mutating tests from explicitly authorized real policy tests. A non-mutating test must prevent real mutation BEFORE launching the app, rather than detect it only afterward. Never erase journals/evidence after failed or unverified restoration. Force-kill tests must target only their owned test process.

## 4. Proposed release architecture

### Operator experience stays simple

Copy/extract a small folder, double-click `WindowsNoSleep.exe`, immediately see a tray icon, click the icon for Settings. No installer or terminal workflow is required by the intended design.

Proposed package:

```text
WindowsNoSleep/
  WindowsNoSleep.exe
  WindowsNoSleep.exe.config   # only if needed by the build
  README.txt
```

Settings, bounded logs and recovery data remain in a stable per-user application-data location, separate from release/test cleanup. Do not require the executable folder to be writable. A one-file EXE is a preference, not a reason to add a packer, embedded script loader or self-extracting runtime.

### Runtime implementation

- Compile C# at build time, not through PowerShell/Add-Type on the destination endpoint.
- Use an ordinary Windows GUI executable: a tray-first UI does not require a hidden PowerShell command.
- No PowerShell, CMD or script-host child process in normal operation or recovery.
- Continue supported power-request and power-policy API contracts, with owned handle lifetimes and precise error reporting.
- Use accurate publisher/product/version metadata and a normal non-elevated manifest.
- Keep display forcing OFF, Battery Safety priority, normal shutdown guard semantics and local diagnostics.
- Do not assume a battery implies a laptop lid: capability detection must distinguish a lid from a desktop/NUC UPS.
- No driver, service, process injection, obfuscation, security bypass, runtime network download or update-service sabotage.

.NET Framework 4.8 is proposed for the small portable footprint and Windows compatibility. Windows 11 originally included 4.8 and later versions include 4.8.1 [R1]. Windows 10 support is conditional on the installed runtime and actual tests; do not promise every historical Windows release or architecture. Initial package target is x64 Windows 11; expand only with evidence.

### Bounded source layout

A small solution can keep logical responsibilities in a few classes rather than introducing a framework:

- `Program` / `TrayApplicationContext` / `SettingsForm`;
- `ProtectionController`;
- `PowerRequestLease` and `PowerPolicyProvider`;
- `BatteryMonitor`;
- `ShutdownGuard`;
- `RecoveryJournal` / `RecoveryCoordinator`;
- focused tests and release/build metadata.

Existing C# interop declarations and PowerShell algorithms are reference material to audit and port, not a reason to copy defects. Keep deterministic test fixtures for the previously observed AC/DC values.

## 5. Recovery contract must not be traded away for fewer alerts

Power requests and policy changes are different lifetimes. A clean exit must release requests and verify restoration of owned policy values. An unclean exit can leave a policy journal and temporary settings needing recovery. The next launch must recover the previous transaction before starting a new one.

Preferred evaluation direction for sign-in recovery: a transparent, documented invocation of the same compiled, signed application, rather than a hidden PowerShell launcher. Only create a recovery startup entry when a NONEMPTY policy transaction actually needs it. Distinguish this clearly from optional everyday `Start with Windows`.

Do not automatically swap RunOnce for a scheduled task, another registry location or a helper that respawns the application. That is not a root-cause fix. Windows documents Run/RunOnce behavior, including deletion and timing constraints; RunOnce is not a continuously recreated general-purpose watchdog [R2]. The exact single sign-in mechanism must be selected and reviewed after the incident evidence and endpoint policy are available, before coding the mutating recovery path.

Required transaction sequence:

1. resolve actual capabilities and narrowly required changes;
2. capture exact original values and a versioned, validated write-ahead journal;
3. establish the approved recovery prerequisites before the first policy write;
4. apply and verify only allowed changes;
5. restore on Stop, Battery Safety, Exit and next-launch recovery;
6. verify original values before clearing journal/owned startup registration;
7. on ambiguous recovery or changed policy ownership, preserve evidence, report the conflict and stop new mutations rather than overwrite another actor's settings.

Recovery data must include sufficient identity to avoid using another machine's, user's or transaction's snapshot. Keep a strict setting allowlist; never accept arbitrary registry/power-setting instructions from a journal. Account for active-scheme drift without reactivating an old scheme, duplicate instances, application-folder moves and inaccessible recovery executable paths.

Important boundary: a portable app cannot promise immediate rollback if security software quarantines both the application and its recovery mechanism, or if power is lost. Do not claim that code signing removes this failure mode. New real-policy trials require an independently preserved, administrator-reviewable original snapshot and a bounded incident-recovery procedure. If the environment does not permit a suitable recovery route, do not apply temporary lid/DC overrides; show the unavailable capability. Reduced protection is a disclosed fallback, not full V1 acceptance.

The first executable pilot below therefore makes NO policy or startup writes. Full closed-lid/DC protection remains a subsequent required product gate. A permanent change to final defaults or a manual-only recovery compromise needs a separate owner decision.

## 6. Signing and distribution

Build an ordinary Release artifact in CI; record source SHA, toolchain, package SHA-256 and signature status. Test the same final bytes that are distributed, including the downloaded ZIP/extracted artifact route. Source or locally built unsigned-file success is not release-package acceptance.

Target Authenticode signing with a trusted, consistent publisher identity and timestamping. Signing keys must stay in an appropriate signing service/secure store, never in the repository or public logs. Self-signing alone is not public reputation or enterprise approval.

Microsoft recommends consistent trusted signing, but newly signed binaries can still receive SmartScreen warnings [R3, R4]. SmartScreen reputation, Defender malware classification, application-control policy and a third-party EDR verdict are separate checks. Do not describe a signature, scan result, extension change or successful CI run as universal antivirus clearance.

If the final legitimate artifact is still detected, use the endpoint administrator's vendor-support route with the exact artifact and sanitized evidence. Microsoft provides a developer submission/dispute process; SentinelOne provides customer support/ticket access [R4, R5]. No promise of a vendor verdict or global whitelist. An explicitly approved enterprise deployment exception, if ever needed, must be recorded as such rather than mislabeled as passing unchanged security policy; it is not the default solution.

## 7. Implementation and validation sequence after owner approval

| Stage | Bounded work | Exit evidence |
| --- | --- | --- |
| A — incident/safety triage | Existing detection evidence, exact contributor SHA, current Windows state and preserved originals; harden unsafe test boundaries in source | Known/unknown facts recorded; no new affected-endpoint execution |
| B — minimal compiled pilot | Portable tray, direct SystemRequired request, Stop/Exit, no policy/startup writes; CI and isolated Windows verification | Build/behavior evidence; exact-artifact protected-endpoint pilot approved separately |
| C — feature port | Battery Safety, supported shutdown guard, settings and mock transaction/recovery tests | New implementation tests pass; no borrowed physical acceptance labels |
| D — recovery design gate | Select ONE documented direct-EXE recovery mechanism, signing/deployment path and ownership rules; independent review | Restore contract and EDR/IT review accepted before real writes |
| E — bounded physical lifecycle | Snapshot; tiny apply/verify/clean restore; then controlled app-crash/next-launch/sign-in recovery in an approved test environment | Exact restore and retained evidence on failure; no unexpected startup/process residue |
| F — product acceptance | AC/DC, lid, display-off/disconnected, headless/NUC, low-battery simulation before physical battery tests, longer idle/overnight run, final package security review | Device/build/package-specific acceptance matrix; all untested cases explicit |

Stage B is deliberately small so the team does not complete a whole port before validating the proposed packaging direction. After its evidence, continue the same lane or revise the proposal; do not spawn competing rewrites.

Do not use a production endpoint as a repeated detection experiment. A security detection stops that trial. Subsequent testing needs reviewed evidence and a new bounded authorization, not renamed variants or exclusions. Never repeatedly rerun the old quarantined path.

No active battery drain to critical, forced machine restart, lid close, monitor unplug, admin elevation or real Windows policy write is authorized by this plan. Those require a separate exact-SHA dispatch.

## 8. Done criteria for Issue #3

- Incident evidence and any uncertainty are documented; vendor rule attribution is not invented.
- Any potentially stranded original endpoint settings/recovery state are reconciled with evidence.
- The hosted-test mutation/cleanup hazard is fixed and tested.
- Runtime packaging and chosen recovery path are transparent and reviewed.
- An exact release-candidate artifact is allowed on the agreed protected test endpoint with its normal security policy; record product/version/policy and test scope.
- Core and, where included, real transaction/recovery behavior pass on that artifact.
- No security disabling, stealth/exclusion workaround, undocumented power changes or loss of exact-restore safety is used to obtain a pass.
- README, PLAN, TEST_PLAN, PROGRESS and PR status distinguish implemented, tested, blocked and unsupported behavior.

Issue #3 stays open and Dispatch 004 stays HOLD until these relevant gates are satisfied and the Control Tower explicitly authorizes a new test. This proposal alone is not a fix.

## References

Repository evidence:

- [Issue #3](https://github.com/bohanyt/windows_no_sleep/issues/3)
- [Production host at reviewed SHA](https://github.com/bohanyt/windows_no_sleep/blob/8059f92f51702c35646e94c8b1afe1e1e3c96934/WindowsNoSleep.ps1)
- [Hosted integration test at reviewed SHA](https://github.com/bohanyt/windows_no_sleep/blob/8059f92f51702c35646e94c8b1afe1e1e3c96934/tests/WindowsIntegrationTests.ps1)
- [Approved product plan](PLAN_V1.md), [current status](../PROGRESS.md), [Control Tower rules](CONTROL_TOWER.md)

Primary external references, checked 2026-09-17:

- R1 — [Microsoft: .NET Framework on Windows](https://learn.microsoft.com/en-us/dotnet/framework/install/on-windows-and-server)
- R2 — [Microsoft: Run and RunOnce registry keys](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)
- R3 — [Microsoft: SmartScreen reputation for developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
- R4 — [Microsoft: software developer FAQ and detection disputes](https://learn.microsoft.com/en-us/defender-xdr/developer-faq)
- R5 — [SentinelOne: customer support](https://www.sentinelone.com/global-services/get-support-now/)
- R6 — [Microsoft: PowerSetRequest](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powersetrequest) — supported idle-sleep request, with explicit lid/user-sleep and Modern Standby/DC limitations.

END_OF_EDR_PLAN key=WNS-ISSUE3-20260917-PROPOSED-V1
