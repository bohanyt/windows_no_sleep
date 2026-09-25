# CONTROL TOWER — windows_no_sleep

Status: active  
Date established: 2026-09-14  
Owner: bohan / `bohanyt`  
Planner / Control Tower: ordinary ChatGPT project chat and its explicitly handed-off successors  
Local Windows executor: Cursor agent on the physical Windows 11 test laptop, **only when explicitly dispatched**

GitHub is the source of truth. Chat memory is convenience only.

Current orientation (2026-09-25): native C# WinForms/.NET Framework 4.8 is the V1 runtime. The single implementation lane is `feat/v1-native-winforms` / OPEN DRAFT PR #4. Issue #1 packet `WNS-PRESTABLE-RECONCILE-20260925-V1` authorizes only a bounded merge/updater/workflow/docs reconciliation after owner acceptance of the exact 0.4.7.0 tested-endpoint physical gates. Independent review and stable release decision remain pending. The old PowerShell Dispatch 004 is prohibited; Issue #3/EDR history remains open and unsigned endpoint acceptance is not universal certification.

---

## 1. Read order for every new Control Tower chat

A successor Control Tower must fresh-read, in this order:

1. `README.md`
2. `docs/PLAN_V1.md`
3. `docs/TEST_PLAN.md`
4. `docs/CONTROL_TOWER.md`
5. `docs/NATIVE_RUNTIME_DECISION.md`
6. `PROGRESS.md`
7. the latest handoff and current master Control Tower issue comments
8. current implementation PR/branch, exact-head CI and release identity

Do not continue from remembered chat state without checking GitHub.

---

## 2. Authority order

When sources conflict, use this order:

1. owner instruction in the current conversation, once written back to GitHub;
2. latest explicit authority update on `main`;
3. `docs/PLAN_V1.md`;
4. latest master Control Tower issue status/comment;
5. `PROGRESS.md`;
6. implementation branch/PR evidence;
7. old chat history.

A product decision made in chat is not durable until the Control Tower writes it into GitHub authority docs or the master issue.

---

## 3. Project size / staffing rule

This is a **small utility with high integration sensitivity**, not a large software system.

Default staffing:

- one Control Tower;
- one implementation owner at a time;
- one physical-Windows executor when real OS/hardware evidence is required;
- optional one independent reviewer for a release candidate or risky power-policy change.

Do **not** create a swarm by default.

Use additional agents only for clearly disjoint work that cannot collide. Never allow two agents to mutate Windows power settings on the same test machine concurrently.

---

## 4. Git / branch model

`main`:

- authority docs;
- accepted stable state;
- progress/handoff information.

Implementation:

- use one feature branch for the current V1 implementation;
- current branch: `feat/v1-native-winforms` / DRAFT PR #4;
- do not create parallel competing implementation branches unless the Control Tower explicitly records why.

A local executor must fresh-pull/fetch before work and must report the exact starting commit SHA.

---

## 5. Local executor rule

The local Cursor agent is a **physical execution/test resource**, not an autonomous planner.

Do not dispatch it merely because code can be written locally. Control Tower/GitHub work should cover source authoring and review where practical.

Dispatch local execution only when one or more of these are actually needed:

- compile/runtime behavior cannot be established without Windows;
- `PowerCreateRequest`/`PowerSetRequest` integration proof;
- `powercfg` observation;
- permission/elevation behavior;
- real active power scheme read/write/restore proof;
- Modern Standby behavior;
- physical lid-close behavior;
- AC/DC transition;
- battery safety behavior;
- tray/notification-area behavior;
- SentinelOne/EDR/AppLocker/PowerShell execution behavior;
- long soak on the intended endpoint.

Every local dispatch must include:

- exact base SHA;
- exact branch;
- exact owned files, if edits are permitted;
- commands/tests to run;
- Windows settings allowed to change;
- Windows settings forbidden to change;
- required before/after snapshots;
- exact evidence to report;
- explicit restore procedure;
- stop conditions.

The local executor must not improvise new product scope.

---

## 6. Windows mutation safety authority

Before any test that changes power policy:

- snapshot active scheme identity;
- snapshot exact original AC/DC values that will be changed;
- persist the values outside transient chat output;
- change only the values authorized by `PLAN_V1.md` and the current dispatch;
- restore in a `finally`/equivalent cleanup path;
- re-read and prove restoration;
- stop if the original state cannot be determined.

Never authorize concurrent power-policy mutation tests.

Never authorize:

- `powercfg /hibernate off`;
- deleting/resizing `hiberfil.sys`;
- disabling Windows Update/Medic/BITS services;
- changing power-button action;
- changing critical-battery action;
- switching the active power plan as the product mechanism;
- unexplained registry power hacks;
- EDR/AV bypass behavior.

---

## 7. Evidence vocabulary

Use these labels consistently:

- `DESIGNED` — specified in GitHub, not yet run on target Windows.
- `STATIC_CHECKED` — source reviewed / mock tests pass, but no target-OS proof.
- `WINDOWS_VERIFIED` — observed on a real Windows target with commands/evidence recorded.
- `LOCAL_VERIFIED` — specifically observed on the current physical test laptop.
- `HEADLESS_VERIFIED` — observed with display off/disconnected/headless-equivalent.
- `LID_VERIFIED` — observed with physical lid close.
- `BATTERY_VERIFIED` — observed on DC with safety behavior tested.
- `EDR_VERIFIED` — actual intended endpoint security allowed the release package.

Do not upgrade evidence labels based on inference.

---

## 8. Daily handoff procedure

At the end of a Control Tower session that materially changes the project:

1. update `PROGRESS.md` with:
   - date/time if useful;
   - exact current phase;
   - exact latest accepted commit/branch/PR;
   - decisions made;
   - evidence gained;
   - known failures/unknowns;
   - next bounded action;
   - whether local executor is currently allowed to act;
2. update the master issue if there is a live implementation/review queue;
3. ensure product decisions are reflected in `docs/PLAN_V1.md` when they changed;
4. give the owner a short copy-paste successor prompt only if a new chat is actually needed.

A successor should be able to reconstruct current state from GitHub without old chat access.

---

## 9. Historical phase at establishment

Current phase: **P0 — Authority and plan**.

At the time this file was created:

- legacy third-party binary has been surveyed;
- no rewrite implementation is accepted yet;
- owner approved beginning the build under GitHub Control Tower;
- plan is intentionally written before source work;
- no local Cursor execution is currently required.

The next normal action after P0 docs are complete is P1 source-safe implementation on a dedicated feature branch.
