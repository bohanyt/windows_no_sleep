# PROGRESS

## [2026-09-14] P2 Dispatch 002 PASS — real local policy transaction verified
- Phase: **P2 — physical Windows integration**.
- Control Tower issue: `#1`.
- DRAFT PR: `#2` on `feat/v1-portable-tray`.
- Exact tested implementation SHA: `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`.
- Dispatch 002 ran once in the separate verification checkout, detached at the exact SHA, normal non-elevated user, AC connected, battery 100%, lid open.
- Mandatory fresh Probe matched the prior snapshot exactly:
  - active scheme Balanced `381b4222-f694-41f0-9685-ff5bb260df2e`;
  - lid `AC=0 / DC=0`;
  - sleep idle `AC=0 / DC=1200` seconds;
  - critical battery `5%`;
  - exactly one proposed change: `SleepIdle`, DC only, `1200 -> 0`.
- Real bounded mutation evidence:
  - write-ahead recovery snapshot was persisted before the first write;
  - only `SleepIdle DC` changed `1200 -> 0`;
  - temporary value was re-read and verified;
  - held about 3 seconds;
  - transaction restore ran;
  - final scheme remained Balanced;
  - lid remained exactly `0/0`;
  - sleep idle restored exactly to `AC=0 / DC=1200`;
  - `MutationAttempted=true`, `MutationApplied=true`, `RestoreAttempted=true`, `RestoreVerified=true`;
  - outcome `APPLY_AND_EXACT_RESTORE_VERIFIED`;
  - `Error=null`;
  - no pending `recovery.json` remained;
  - tracked worktree clean.
- No lid/display/hibernate/AC policy was changed and no execution-policy/EDR bypass was used.
- Evidence status now includes **`LOCAL_POLICY_TRANSACTION_VERIFIED`**.
- Production tray runtime still does **not** automatically apply the lid/DC transaction. That source integration remains pending.
- Next bounded step: a short **non-mutating physical lid/display-off witness on AC** using the real tray app plus an independent heartbeat workload. If clean, wire the already-proven transaction into the production tray lifecycle and then test AC->DC / closed-lid behavior with the integrated build.

## [2026-09-14] P2 Dispatch 001 PASS — read-only laptop probe verified
- Exact SHA: `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`.
- Endpoint allowed Windows PowerShell 5.1 + `Add-Type` without bypass.
- Laptop snapshot:
  - Windows 11 25H2 family / NT `10.0.26200.0`;
  - Modern Standby S0 Low Power Idle, network connected;
  - Balanced plan;
  - lid already `Do Nothing` on AC and DC (`0/0`);
  - sleep idle `AC=0 / DC=1200`;
  - critical battery `5%`;
  - non-elevated `powercfg /requests` unavailable by permission as expected;
  - no mutation; tracked worktree clean.
- Evidence: `LOCAL_READ_ONLY_VERIFIED`.

## Hosted implementation evidence
At current implementation head `63ea8c99bd90b5416d00d6bec827a8b9e27b8218`, Windows PowerShell 5.1 CI is green for:
- repository-wide parser/static/core tests;
- real read-only `powrprof.dll` power-policy reads;
- deterministic transaction/rollback/recovery tests;
- hosted Windows non-mutating E2E: real tray process reaches `PROTECTED`, request visibility where permitted, second-instance behavior, process-kill cleanup, and unchanged active power plan/query before vs after.

Evidence: `HOSTED_WINDOWS_E2E_GREEN`, `POLICY_TRANSACTION_FAKE_VERIFIED`.

## Product/safety authority
- Keep the **computer/workloads** running; display may dim, turn off, or be absent.
- Protection defaults ON. Battery protection defaults ON. Battery Safety base threshold is 15%.
- Windows/OEM critical-battery action wins. Never disable the hibernation feature or critical-battery mechanism.
- Do not disable Windows Update/Medic/BITS or use undocumented update hacks.
- No permanent power-plan/lid/sleep mutations.
- Normal unattended restart/shutdown blocking is in scope; forced OS/admin/firmware restart remains a platform boundary.
- No EDR bypass behavior.
- Small utility: one Control Tower + one bounded local Windows executor; no swarm by default.

## Remaining release gates
- production runtime wiring of temporary DC/lid policy transaction;
- `LID_VERIFIED` physical closed-lid workload witness;
- `BATTERY_VERIFIED` AC->DC + Battery Safety behavior;
- `HEADLESS_VERIFIED` display-off/disconnected/headless-equivalent workload witness;
- longer Modern Standby/overnight soak;
- SentinelOne/production EDR acceptance of final package.