# PROGRESS

## Current status — 2026-09-14

Phase: **P2 — physical Windows integration / production recovery gate**.

GitHub is the source of truth. DRAFT PR #2 remains the implementation lane on `feat/v1-portable-tray`.

### Current implementation

- Frozen implementation/test head for the next local gate: `8059f92f51702c35646e94c8b1afe1e1e3c96934`.
- Portable Windows PowerShell 5.1 tray utility starts Protection immediately and opens Settings from the tray.
- Core awake path: `PowerCreateRequest` / `PowerSetRequest(PowerRequestSystemRequired)`; display forcing remains OFF by default.
- Normal shutdown/restart guard, single-instance ownership, battery observation, settings/logging, power-policy reads, transactional write-ahead recovery, exact restore, active-plan drift handling, and local verification harnesses exist.
- Production tray runtime now uses the transactional power-policy layer:
  - on laptops, temporary LidAction -> `Do Nothing` only where the original is not already `0`;
  - temporary SleepIdle override is DC-only -> `0` (`Never`) when battery protection is enabled;
  - Stop Protection, Battery Safety, Exit and startup recovery call exact restore;
  - pending recovery is restored before a new protected session;
  - active power-plan drift restores the old scheme without reactivating it, then binds a fresh transaction to the user's current scheme;
  - a temporary HKCU `RunOnce` recovery hook is installed before policy write and removed after verified restore;
  - `-RecoveryOnly` exists for crash/sign-in recovery.
- `src/WindowsNoSleep.RuntimePolicy.psm1` keeps laptop policy planning/lifecycle separate from tray UI.
- `tools/LocalProductionRecoveryWitness.ps1` is the bounded production crash-recovery witness authorized by Dispatch 004.

### Hosted evidence at current head

Windows PowerShell 5.1 CI is fully green at `8059f92f51702c35646e94c8b1afe1e1e3c96934`:

- repository-wide parser/static/core tests;
- real read-only `powrprof.dll` power-policy tests;
- transaction/rollback/recovery tests;
- runtime-policy lifecycle tests;
- hosted Windows non-mutating full tray E2E.

The hosted E2E launches the real tray process, observes `PROTECTED`, exercises singleton behavior and process-scoped request cleanup, and proves the hosted no-battery machine's power plan remains unchanged.

Evidence: `HOSTED_WINDOWS_E2E_GREEN`, `POLICY_TRANSACTION_FAKE_VERIFIED`, `RUNTIME_POLICY_TESTED`.

### Dispatch 001 — local read-only probe: PASS

Physical owner laptop:

- Windows 11 25H2 family / NT `10.0.26200.0`;
- normal non-elevated user; PowerShell/Add-Type allowed by endpoint security;
- active plan Balanced `381b4222-f694-41f0-9685-ff5bb260df2e`;
- LidAction `AC=0 / DC=0` (`Do Nothing`) already;
- SleepIdle `AC=0 / DC=1200s`;
- critical battery threshold `5%`;
- Modern Standby S0 Low Power Idle, network connected;
- non-elevated `powercfg /requests` denied as expected;
- no mutation and clean tracked worktree.

Evidence: `LOCAL_READ_ONLY_VERIFIED`.

### Dispatch 002 — direct real apply/restore smoke: PASS

- fresh preflight matched baseline;
- only SleepIdle DC changed `1200 -> 0`;
- temporary value verified;
- exact restore returned `0 -> 1200`;
- scheme and LidAction unchanged;
- no pending recovery afterward.

Evidence: **`LOCAL_POLICY_TRANSACTION_VERIFIED`**.

### Dispatch 003 — AC closed-lid workload witness: PASS

Implementation SHA: `213c37a86a80d17e58116dee9b4b3ac86f16184f`.

- real tray app reached `PROTECTED`;
- physical lid was closed for about 90 seconds during the 120-second witness;
- independent heartbeat continued with maximum observed gap about **1.046 seconds**;
- machine was responsive after reopening;
- Windows power settings were unchanged.

Important evidence boundary: an external monitor remained connected during this witness. Therefore this proves **closed-lid AC workload continuation with an external display attached**, not full headless operation.

Evidence: **`LID_CLOSED_AC_EXTERNAL_DISPLAY_VERIFIED`**.  
Do not label this `HEADLESS_VERIFIED` yet.

### Dispatch 004 — READY

Authority: `docs/LOCAL_DISPATCH_004.md` on `main`.

Exact frozen implementation SHA: `8059f92f51702c35646e94c8b1afe1e1e3c96934`.

Dispatch 004 runs the real production tray runtime on AC with lid open and verifies:

1. production app reaches `PROTECTED`;
2. owner laptop changes only SleepIdle DC `1200 -> 0`;
3. exact recovery snapshot + recovery startup hook exist while active;
4. tray process is intentionally force-killed to simulate an unclean crash;
5. temporary DC value + recovery state survive the process crash;
6. production `-RecoveryOnly` restores exactly to DC `1200`;
7. recovery snapshot and startup hook disappear only after exact restore.

No battery unplug, lid test, machine sleep/restart, manual powercfg mutation, elevation, source edit or EDR bypass is authorized.

Local Cursor executor status: **DISPATCH 004 READY**.

### Product/safety authority

- Keep the **computer/workloads** running; display may dim, turn off, or be absent.
- Protection defaults ON. Battery protection defaults ON. Battery Safety base threshold is 15%; Windows/OEM critical battery behavior remains authoritative.
- Never disable hibernation feature, critical-battery behavior, Windows Update/Medic/BITS, or use undocumented power/update hacks.
- No permanent power-plan/lid/sleep mutation.
- Normal unattended restart/shutdown blocking is in scope; forced OS/admin/firmware restart is a platform boundary.
- No EDR bypass behavior.
- Small utility: one Control Tower + one bounded physical Windows executor; no swarm by default.

### Remaining release gates after Dispatch 004

- production crash-recovery lifecycle verified on the owner laptop;
- production clean Stop/Exit exact-restore witness;
- `BATTERY_VERIFIED` AC->DC behavior and Battery Safety behavior;
- `HEADLESS_VERIFIED` with external display off/disconnected (or true NUC/headless endpoint);
- longer Modern Standby/overnight soak;
- SentinelOne/production EDR acceptance of the final portable package;
- final independent release review before PR #2 is marked ready/merged.
