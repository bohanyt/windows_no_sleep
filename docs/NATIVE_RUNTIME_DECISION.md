# Native runtime decision — owner approved

Status: **OWNER-APPROVED IMPLEMENTATION AUTHORITY**  
Date: 2026-09-17  
Repository: `bohanyt/windows_no_sleep`  
Incident: Issue #3  
Supersedes: the PowerShell-first runtime/packaging lane for the next implementation work

## Current implementation addendum — 2026-09-25

The decision below established the first native pilot. The current V1 runtime is the compiled x64 C# WinForms/.NET Framework 4.8 app on `feat/v1-native-winforms` / DRAFT PR #4. It now includes the approved seven-feature bundle, screensaver/local inactivity protection and a transient DisplayRequired request only during qualifying Modern Standby DC protection. The owner accepted focused physical gates for the exact 0.4.7.0 EXE on the tested endpoint. Independent release review and stable publication remain pending.

The later owner-approved exception to the original no-helper wording is a bounded elevated machine-inactivity broker. It starts only after explicit UAC for that operation, restores the exact original machine-inactivity value if the main process disappears, then exits. It is not a general recovery service. Other pending policy recovery still relies on ARR where invoked and the durable next-launch journal. The old PowerShell Dispatch 004 remains prohibited. Issue #3 records the former PowerShell security incident; the unsigned native build has no universal EDR certification.

## Decision

The next V1 implementation lane will be a conventional compiled Windows application, not a PowerShell-hosted production runtime.

Target for the first native lane:

- C# WinForms;
- .NET Framework 4.8;
- ordinary portable `WindowsNoSleep.exe`;
- normal non-elevated manifest;
- no installer required for the pilot;
- no PowerShell/CMD/script-host child process in normal operation;
- no embedded/extracted PowerShell payload;
- no obfuscation, packer, runtime download, AV/EDR bypass or automatic elevation.

The operator contract is unchanged: double-click -> Protection starts -> tray icon -> click tray icon for Settings.

## Recovery direction

The recovery contract remains mandatory, but the PowerShell `RunOnce` + hidden `-RecoveryOnly` mechanism is retired for the native lane.

The selected native recovery design is layered:

1. **Durable recovery journal** in per-user application data, written before any temporary policy mutation.
2. **Windows Application Recovery and Restart (ARR)** using `RegisterApplicationRecoveryCallback` and `RegisterApplicationRestart` for conventional crash/hang recovery where Windows invokes those contracts.
3. **Restore-before-protect on every normal launch**: if a previous journal is pending, exact originals must be restored and verified before a new protection session may mutate policy.

ARR is best-effort, not a guarantee for force-kill, EDR termination, power loss or kernel failure. The durable next-launch journal remains the final recovery path for those cases.

No `RunOnce`, scheduled task or service is part of the native V1 recovery design. The later explicitly approved machine-inactivity broker exception is described above.

If a safe recovery route cannot be established for a policy mutation on a target endpoint, that capability must fail closed rather than leave an unbounded temporary policy change.

## Signing decision

Do **not** purchase or require a signing certificate yet.

The first native pilot is intentionally unsigned and minimal so we can validate whether a boring compiled application is accepted by the protected endpoint before paying for signing or porting the full feature set.

Signing remains a later release/deployment decision. It must not be treated as an antivirus bypass or a substitute for protected-endpoint testing.

## Implementation lane

Use one new implementation branch:

`feat/v1-native-winforms`

The old PowerShell DRAFT PR #2 becomes reference/history and must not remain an active competing implementation lane.

The first native milestone is deliberately non-mutating:

- tray application;
- immediate `PowerRequestSystemRequired` lease;
- Start/Stop Protection;
- Exit cleanup;
- simple Settings/status UI;
- no lid/DC power-policy writes;
- no registry startup writes;
- no recovery persistence yet because there is no policy mutation to recover;
- build artifact and SHA-256 produced by CI.

This first-pilot staging rule is historical. The bundled native implementation and owner physical gates have since advanced as recorded in `PROGRESS.md` and `docs/NATIVE_V1_ACCEPTANCE.md`.

## Safety and test rules

- The old quarantined PowerShell integration path stays on HOLD.
- Do not rerun it on the affected endpoint.
- Do not add AV/EDR exclusions or weaken endpoint security to obtain a pass.
- Physical acceptance labels from the PowerShell build do not automatically certify the native build.
- The original non-mutating pilot required a new exact-SHA dispatch before real power-policy writes; that pilot sequencing is historical after the subsequent owner-authorized bundle and physical gates.

Issue #3 remains open until the native package and recovery design satisfy the documented protected-endpoint and exact-restore gates.

END_OF_NATIVE_RUNTIME_DECISION key=WNS-NATIVE-20260917-APPROVED-V1
