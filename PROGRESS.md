# PROGRESS

## Current status — 2026-09-14

Phase: **P2 — physical Windows integration**.

GitHub is the source of truth. DRAFT PR #2 remains the implementation lane on `feat/v1-portable-tray`.

### Current implementation

- Head: `213c37a86a80d17e58116dee9b4b3ac86f16184f`.
- Portable Windows PowerShell 5.1 tray utility starts Protection immediately and opens Settings from the tray.
- Core awake path uses `PowerCreateRequest` / `PowerSetRequest(PowerRequestSystemRequired)`; display forcing is OFF by default.
- Shutdown/restart guard, single-instance ownership, battery observation, settings/logging/recovery helpers, read-only power-policy provider, temporary-policy planner, write-ahead transaction, rollback, and exact restore logic exist.
- Added `tools/LocalLidWitness.ps1`, a non-mutating physical witness harness that launches the real tray app, waits for `PROTECTED`, writes a one-second heartbeat, and detects execution gaps while the physical lid/internal display is closed.
- Production tray runtime still does **not yet automatically apply** the lid/DC policy transaction. That source integration remains the next implementation step after the physical witness.

### Hosted evidence

At current head `213c37a86a80d17e58116dee9b4b3ac86f16184f`, Windows PowerShell 5.1 CI is green for:

- repository-wide parser/static/core tests, including tools;
- real read-only Windows `powrprof.dll` power-policy reads;
- deterministic transaction/rollback/recovery tests;
- hosted Windows non-mutating E2E: real tray process reaches `PROTECTED`, request visibility where permitted, second-instance behavior, process-kill cleanup, and unchanged active power plan/query before vs after.

Evidence: `HOSTED_WINDOWS_E2E_GREEN`, `POLICY_TRANSACTION_FAKE_VERIFIED`.

### Dispatch 001 — local read-only probe: PASS

Physical laptop evidence at implementation SHA `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`:

- Windows 11 25H2 family / NT `10.0.26200.0`;
- Windows PowerShell `5.1.26100.9444`;
- normal non-elevated user; endpoint security allowed `powershell.exe -NoProfile -File` and `Add-Type`;
- active plan: Balanced `381b4222-f694-41f0-9685-ff5bb260df2e`;
- lid already `AC=0 / DC=0` (`Do Nothing`), so this laptop needs no lid policy write;
- sleep idle `AC=0 / DC=1200s`;
- critical battery threshold `5%`;
- Modern Standby S0 Low Power Idle, network connected; S3/Hibernate/Hybrid/Fast Startup unavailable;
- non-elevated `powercfg /requests` unavailable by permission as expected;
- no mutation and clean tracked worktree.

Evidence: `LOCAL_READ_ONLY_VERIFIED`.

### Dispatch 002 — real apply/restore smoke: PASS

Same laptop, normal non-elevated user, AC connected, lid open.

- mandatory fresh Probe matched baseline exactly;
- write-ahead snapshot existed before first write;
- only `SleepIdle DC` changed `1200 -> 0`;
- temporary value re-read and verified;
- held about 3 seconds;
- exact restore returned `DC 0 -> 1200`;
- final Balanced scheme unchanged;
- lid remained `0/0`;
- sleep idle restored exactly `AC=0 / DC=1200`;
- `MutationAttempted=true`, `MutationApplied=true`, `RestoreAttempted=true`, `RestoreVerified=true`;
- outcome `APPLY_AND_EXACT_RESTORE_VERIFIED`, `Error=null`;
- no pending recovery file and clean tracked worktree.

Evidence: **`LOCAL_POLICY_TRANSACTION_VERIFIED`**.

### Dispatch 003 — READY

Authority: `docs/LOCAL_DISPATCH_003.md` on `main`.

Exact implementation SHA: `213c37a86a80d17e58116dee9b4b3ac86f16184f`.

This is a **non-mutating AC closed-lid workload witness** only:

- harness requires the verified Balanced/lid/sleep baseline and AC online;
- real tray app must reach `PROTECTED` first;
- operator closes physical lid for about 90 seconds during a 120-second heartbeat window;
- success requires `LID_CLOSED_WORKLOAD_CONTINUED` with max heartbeat gap <=5s;
- no power-policy write, battery unplug, sleep/restart test, elevation, source edit, or EDR bypass is authorized.

Local Cursor executor status: **DISPATCH 003 READY**.

### Product/safety authority

- Keep the **computer/workloads** running; display may dim, turn off, or be absent.
- Protection defaults ON. Battery protection defaults ON. Battery Safety base threshold is 15%.
- Windows/OEM critical-battery behavior wins. Never disable hibernation feature or critical-battery mechanism.
- Do not disable Windows Update/Medic/BITS or use undocumented update hacks.
- No permanent power-plan/lid/sleep mutations.
- Normal unattended restart/shutdown blocking is in scope; forced OS/admin/firmware restart is a platform boundary.
- No EDR bypass behavior.
- Small utility: one Control Tower + one bounded local Windows executor; no swarm by default.

### Remaining release gates

- `LID_VERIFIED` physical closed-lid workload witness;
- production runtime wiring of temporary DC/lid policy transaction;
- `BATTERY_VERIFIED` AC->DC + Battery Safety behavior;
- `HEADLESS_VERIFIED` display-off/disconnected/headless-equivalent workload witness;
- longer Modern Standby/overnight soak;
- SentinelOne/production EDR acceptance of final package.