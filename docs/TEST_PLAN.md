# Windows No Sleep — V1 Safe Test Plan

Status: authoritative V1 test contract  
Date: 2026-09-14

This plan exists because the project is small, but its failure modes can affect real Windows power behavior. A test is not successful unless restoration is also proven.

---

## 1. Test principles

1. Prefer non-mutating tests first.
2. Never change more Windows power settings than the exact test requires.
3. Read and persist the original value before changing anything.
4. Restore in cleanup even when the test fails.
5. Re-read the setting after restore; do not assume restoration succeeded.
6. Keep the product non-admin where possible; an elevated observer terminal may be used for diagnostics such as `powercfg /requests`.
7. Do not use the physical laptop for broad exploratory power-plan edits.
8. Never drain a battery to a dangerous level merely to prove a threshold.
9. Never run lid/DC/power-policy mutation tests concurrently.
10. Evidence must distinguish mock/static tests from real Windows observation.

---

## 2. Current physical test machine baseline

From the initial survey:

- Windows 11 Pro for Workstations 25H2;
- build `26200.9445`;
- x64;
- Modern Standby S0 Low Power Idle only; S3 unavailable;
- battery present;
- active plan: Balanced;
- display off AC: Never;
- display off DC: 10 minutes;
- sleep AC: Never;
- sleep DC: 20 minutes;
- hibernate feature/settings must not be globally changed;
- survey session was non-elevated.

Before future integration testing, refresh this baseline rather than assuming it stayed unchanged.

---

## 3. Test layers

### T0 — Static/source checks

No Windows state mutation.

Prove:

- script parses/loads;
- configuration defaults are deterministic;
- state transitions are idempotent;
- recovery JSON serialization/deserialization works;
- corrupt settings fail safely;
- corrupt recovery state prevents blind mutation;
- battery threshold/hysteresis logic is deterministic;
- Start/Stop called repeatedly does not duplicate ownership;
- restore plan only contains settings actually changed by the app.

Evidence label: `STATIC_CHECKED`.

### T1 — Tray/UI smoke

No power-plan mutation.

Prove:

- double-click launcher starts one instance;
- no Settings window appears automatically;
- tray icon appears;
- clicking icon opens Settings;
- second launch does not create a second protection owner;
- Exit removes tray icon cleanly;
- status state is visible;
- logs/settings directory can be created without requiring program-folder write access.

### T2 — Power request lifecycle

No power-plan mutation.

Prove:

- `PowerCreateRequest` succeeds;
- `PowerRequestSystemRequired` is set;
- default path does not set `DisplayRequired`;
- request is visible in `powercfg /requests` when observed from an elevated terminal where required;
- Stop Protection clears request;
- clean Exit clears request;
- force-closing the process does not leave a permanent request behind;
- restart of the app can recover to a clean state.

Expected display behavior: monitor is still allowed to time out.

### T3 — Shutdown/restart blocker lifecycle

No update policy mutation.

Use a safe manual shutdown/restart attempt only after unsaved work is closed.

Prove:

- blocker exists while normal Protection is active;
- a normal session-end request is blocked with a useful reason where Windows honors the application contract;
- Stop Protection/Exit removes the blocker;
- Battery Safety path removes the blocker;
- the user retains an explicit force/override path through Windows;
- app logs the attempt and final session-end outcome if observable.

Do not claim this proves every Windows Update forced-restart path.

### T4 — Recovery transaction without real plan mutation

Use a fake provider or harmless test value where possible.

Prove ordering:

1. read originals;
2. write recovery snapshot;
3. mark restore required;
4. mutate;
5. stop/exit;
6. restore;
7. verify;
8. clear recovery requirement.

Simulate process interruption between each stage and prove next launch behavior.

### T5 — Real lid-setting transaction

Local executor required.

Before test:

- record active scheme GUID;
- read exact original AC lid action;
- read exact original DC lid action;
- save evidence externally/in test log;
- confirm values are readable before proceeding.

Test:

- app writes recovery snapshot first;
- app sets only authorized lid action(s) to `Do Nothing`;
- confirm changed value;
- Stop Protection;
- confirm exact original values restored;
- repeat with Exit;
- simulate an unfinished recovery snapshot and confirm next launch restores before new mutation.

Physical lid-close test comes only after the transaction itself is proven.

### T6 — Closed-lid AC behavior

Local executor required.

Preconditions:

- lid transaction T5 passed;
- laptop connected to AC;
- a harmless heartbeat workload records a timestamp periodically;
- remote recovery/access path is available if practical.

Test:

- start Protection;
- close lid;
- leave closed longer than the normal trigger interval;
- reopen;
- prove heartbeat continuity and app state;
- prove display behavior did not become part of the awake contract;
- Stop/Exit and prove lid policy restoration.

Evidence label only after physical test: `LID_VERIFIED`.

### T7 — Display-off / headless-equivalent behavior

For laptop/desktop/NUC as available:

- allow display to turn off naturally or physically turn the external monitor off;
- where safe, disconnect display cable after protection is established;
- keep a heartbeat workload running;
- wait beyond a meaningful idle interval;
- prove workload continuity.

The app must not infer failure merely because no active monitor is present.

Evidence label: `HEADLESS_VERIFIED` for the tested scenario.

### T8 — DC / Modern Standby timeout transaction

Local executor required.

Do not begin until the exact minimum settings needed are identified.

Before mutation:

- refresh active scheme;
- snapshot the exact AC/DC sleep/hibernate values being considered;
- do not change display timeout unless the specific test requires it;
- write recovery evidence.

If an accelerated timeout is needed for testing, temporarily shorten only the relevant timeout after recording its original value.

The product protection path may temporarily set the required DC sleep/hibernate timeout(s) to Never only if T8 proves this is required for indefinite DC operation.

After every run:

- restore all changed values;
- re-read and compare to originals;
- record pass/fail.

### T9 — Battery Safety without dangerous drain

Prefer dependency injection/simulation for threshold crossing first.

Real battery test should validate transition behavior without intentionally draining to near-empty if a safe method is available.

Prove:

- normal DC Protection state;
- effective threshold calculation;
- crossing threshold enters `BATTERY SAFETY`;
- power request clears;
- shutdown blocker clears;
- temporary lid/sleep/hibernate values restore;
- tray state changes;
- AC reconnect exits Battery Safety and may resume Protection;
- percentage hysteresis prevents rapid flapping.

Do not change Windows Critical Battery Action or its threshold just to force the test.

### T10 — Sleep/idle soak

Only after short integration tests pass.

Recommended progression:

- 5–10 minute accelerated test;
- 30–60 minute test;
- multi-hour/overnight soak.

Use a heartbeat file/log external to the UI so continuity can be audited.

For overnight test, first prove recovery/restore paths during the day.

### T11 — Update/restart observation

Do not manufacture a production Windows Update restart by damaging update state.

First prove only the application shutdown blocker contract with normal restart requests.

Then observe naturally occurring Windows Update restart behavior when a safe opportunity exists. Record:

- whether session-end message was received;
- blocker state;
- whether Windows honored or overrode it;
- whether the machine actually rebooted;
- whether autostart (if enabled for the test) brought protection back after login.

A forced deadline/reboot that overrides the app is a documented platform boundary, not permission to disable Windows Update services.

### T12 — Autostart

Default product setting remains OFF.

When testing enabled state:

- use only the selected per-user non-admin mechanism;
- log off/on or reboot at a safe time;
- verify a single instance starts;
- verify disabling autostart removes exactly what the app created;
- no scheduled task/service leftovers.

### T13 — Packaging / EDR

Local endpoint test required for final packaging decision.

Prove actual operator path:

1. copy/download release folder;
2. double-click launch file;
3. observe PowerShell execution policy behavior;
4. observe SentinelOne/other EDR reaction where available;
5. verify there is no encoded command, obfuscation, or persistent policy bypass;
6. record whether the package is usable without local admin.

If blocked by organizational policy, stop. Do not add evasion behavior. Escalate packaging decision to Control Tower.

---

## 4. Forbidden test mutations

A test must stop rather than do any of these without a new explicit owner-approved plan:

- `powercfg /hibernate off`;
- delete/resize `hiberfil.sys`;
- disable Windows Update service;
- disable Windows Update Medic Service;
- disable BITS;
- disable Task Scheduler;
- change critical-battery action;
- change power-button action;
- set broad unrelated power settings to Never;
- replace the active power scheme;
- create a permanent factory power plan;
- write undocumented registry hacks;
- use forced EDR/AV bypass techniques.

---

## 5. Restore checklist for every mutating test

Before declaring a mutating test complete, report:

```text
active_scheme_before:
changed_settings:
  - setting:
    ac_before:
    dc_before:
    ac_test_value:
    dc_test_value:
restore_attempted: yes/no
ac_after:
dc_after:
active_scheme_after:
exact_restore_verified: yes/no
recovery_snapshot_cleared: yes/no
unexpected_changes: none / list
```

If `exact_restore_verified` is not `yes`, the next action is restoration/recovery — not additional feature testing.

---

## 6. Local executor stop conditions

Stop immediately and report to Control Tower if:

- original setting cannot be read;
- active scheme changes unexpectedly during the test;
- restore fails;
- permission/elevation behavior is different from the dispatch assumption;
- endpoint security quarantines or blocks a component;
- machine becomes difficult to wake/control;
- battery drops faster than expected;
- Windows enters an undocumented state;
- test would require changing an unapproved setting.

No improvisation after a stop condition.
