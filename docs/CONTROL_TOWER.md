# Maintainer coordination / Control Tower

**Current phase: post-release maintenance.** Windows No Sleep V1 is released; PR #4 is merged. Start with [CURRENT.md](CURRENT.md) for release identity and known follow-up work.

Owner: Bohan / `bohanyt`. GitHub is the source of truth; chat history is not a replacement for current repository state.

## Read order

For maintenance, read `docs/CURRENT.md`, this file, and the latest [Issue #1](https://github.com/bohanyt/windows_no_sleep/issues/1) comments. Then inspect the current refs, claims, relevant files, and task-specific evidence. Read [the V1 plan](PLAN_V1.md), [test plan](TEST_PLAN.md), and [native runtime decision](NATIVE_RUNTIME_DECISION.md) when behavior or safety is affected.

Older handoffs and dispatches are indexed in [the archive](archive/README.md). They are not live instructions. The former single V1 implementation lane is complete; do not reopen it merely because an old document says it is active.

## Authority and scope

Current owner instructions must be recorded on GitHub before they become durable project decisions. Follow the latest explicit authority on main and in the coordination issue. Treat older phase/status text as historical; preserve the behavior and safety contracts unless a new change is explicitly authorized.

Keep staffing small: one maintainer/Control Tower, one implementation owner at a time, and a physical-Windows operator only when needed. A focused documentation task must not quietly turn into a runtime, workflow, signing, licensing, or release change.

Do not overwrite concurrent work or force-push. Check the expected branch head before publication. Use the current task's branch policy; the completed PR #4 does not require future unrelated work to reuse its branch.

## Windows safety

Before any real policy-mutation test, obtain explicit scope and permission, snapshot scheme identity and exact original values, persist evidence, specify permitted keys, and provide a restore procedure. Verify restoration by reading values back. Never run concurrent power-policy mutation tests.

Never authorize global hibernation disable, hiberfil deletion/resizing, Windows Update/Medic/BITS sabotage, power-button or critical-battery action changes, power-plan switching as the product mechanism, unexplained registry hacks, or antivirus/EDR bypasses.

Local execution is reserved for evidence that actually requires Windows or physical hardware, including ABI/build/runtime integration, UAC, recovery, power requests, lid, battery, standby, tray, and endpoint-security behavior. Documentation cleanup does not justify another physical acceptance campaign.

## Evidence and handoff

Keep evidence labels precise: `DESIGNED`, `STATIC_CHECKED`, `WINDOWS_VERIFIED`, `LOCAL_VERIFIED`, `HEADLESS_VERIFIED`, `LID_VERIFIED`, `BATTERY_VERIFIED`, and `EDR_VERIFIED` describe different proof scopes. Never infer physical or security acceptance from source review, compilation, or fake-provider tests.

Record source/EXE identity, changes, tests actually run, remaining uncertainty, and the next bounded action in the coordination issue. Update `CURRENT.md` when status changes. Keep the current summary readable and preserve old evidence through immutable commit links rather than presenting an ever-growing pre-release diary as today's status.

## Release boundary

A documentation-only main commit does not change the published EXE or its version. Preserve published tag and asset identity. Runtime/package/version changes require their own evidence and owner release decision. The V1 exact-artifact promotion and remaining workflow follow-up are recorded in [CURRENT.md](CURRENT.md).
