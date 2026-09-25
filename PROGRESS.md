# PROGRESS

## Current status — 2026-09-25 v1.0.0 pre-merge metadata

Issue #1 packet `WNS-V1-PREMERGE-20260925-V1` follows CT release decision comment `5829142335`. SAME `feat/v1-native-winforms` / OPEN DRAFT PR #4. Starting head `deb4e04f225a61c2f4e0a85f07ca52247b3190d8`.

Assembly and manifest identity are now `1.0.0.0` / `WindowsNoSleep`. This is a release candidate for unpublished stable tag `v1.0.0`. Functional native logic is unchanged from the accepted 0.4.7 lineage. Exact 0.4.7.0 physical evidence remains SHA-256 `7a62745e408792a0c1c3d4e863e0f46a3af7fc9c18e53b567d0be87fbd397e74` at `ab1e0f1035c553e6474b2866637191d1406a9cfb` and does not accept this candidate's hash.

`native-v1` pushes on this feature branch and on `main`. `dev-latest` publishes only when the triggering branch still points at the run. The stable tag workflow promotes that exact successful `main` artifact and does not rebuild. Until `v1.0.0` exists, the updater still requires `dev`. Issue #3 and the machine-inactivity recovery limits remain in force. No merge, tag, or stable publication is authorized by this packet.

---

## Historical status — 2026-09-25 pre-stable reconciliation

Issue #1 packet `WNS-PRESTABLE-RECONCILE-20260925-V1` authorizes one bounded implementation worker on the SAME `feat/v1-native-winforms` branch and OPEN/DRAFT/unmerged PR #4. Main authority and the 2026-09-21/23/25 handoffs are preserved as history. Native C# WinForms/.NET Framework 4.8 is the current V1 runtime; the PowerShell-first lane and old Dispatch 004 remain superseded/prohibited.

The owner accepted focused physical evidence on the tested endpoint for the exact native `0.4.7.0` EXE, SHA-256 `7a62745e408792a0c1c3d4e863e0f46a3af7fc9c18e53b567d0be87fbd397e74`, source head `ab1e0f1035c553e6474b2866637191d1406a9cfb`. Exact-head workflow `36085094582` succeeded and `dev-latest` release `396226381` carried that build. Accepted gates include Modern Standby DC idle >600 seconds without lock and AC DisplayRequired release; broker hard-kill restore of exact machine inactivity `900` (`0x384`) and broker self-exit; previously observed Start with Windows reboot/login with expected UAC; Stop through the live broker; and the earlier lid/restart/basic restoration observations. These are endpoint-specific observations, not universal guarantees or EDR certification. Issue #3 remains explicit.

This packet reconciles `main`, updater integrity and channel selection, a gated stable publication mechanism, and current documentation without changing native EXE source or binary metadata. The executable identity must be compared after exact-head CI. PR #4 remains DRAFT/unmerged. Independent release review and the stable release decision are still pending; no stable release is authorized by this packet. Retained reviewer questions S1 administrator-denial latch scope, S2 broker PID-only parent liveness, and S3 broker named-event WorldSid FullControl ACL remain for reviewer disposition.

---

## Historical status — 2026-09-25 physical gate pending

Phase: **Native V1 0.4.7 Modern Standby DC physical acceptance before stable**.

GitHub is the source of truth. Current durable successor handoff:

`docs/CONTROL_TOWER_HANDOFF_20260925.md`

Required sentinel:

`END_OF_CONTROL_TOWER_HANDOFF key=WNS-CT-20260925-V1-047-DC-PHYSICAL-PENDING sections=18`

Active implementation remains SAME `feat/v1-native-winforms` / DRAFT PR #4 at `ab1e0f1035c553e6474b2866637191d1406a9cfb`, binary version `0.4.7.0`.

Exact-head workflow `36085094582` / job `107915092623` succeeded, including Windows SDK ABI check, Release x64 build, PowerRequest self-test, regression suite, packaging and rolling publication. Current `dev-latest` release `396226381` targets that exact head. EXE SHA-256: `7a62745e408792a0c1c3d4e863e0f46a3af7fc9c18e53b567d0be87fbd397e74`.

0.4.7 corrects the owner-proven Modern Standby battery/DC lock path by adding a transient `PowerRequestDisplayRequired` only on qualifying Modern Standby DC protection. It does not mutate the display timeout, password-on-wake or a new power-plan key.

Owner physical evidence already shows the exact 0.4.7 build installed, normal clean restoration, Protected state, and after unplugging:
`DISPLAY_REQUIRED_ACTIVE reason=modern_standby_dc`.

Immediate pending gate: leave the lid OPEN and input idle on DC for >600 seconds (target 11–12 minutes). PASS requires no prior lock/password recurrence. Reconnect AC afterward and verify DisplayRequired releases while normal Protection remains active.

After this passes, do not restart already accepted lid/UAC/restart tests. Continue only still-unproven broker/final gates, then pre-stable packaging/docs reconciliation, independent release review, and only then any merge/stable decision.

PR #4 remains OPEN/DRAFT/unmerged and currently reports a dirty conflict against main. Do not resolve that during the physical gate.

---

## Historical progress retained below

## Current status — 2026-09-23

Phase: **Native V1 final changed-path acceptance before stable**.

GitHub is the source of truth. Durable successor handoff:

`docs/CONTROL_TOWER_HANDOFF_20260923.md`

Required sentinel:

`END_OF_CONTROL_TOWER_HANDOFF key=WNS-CT-20260923-V1-046-UAC-BROKER-PENDING sections=18`

Active implementation remains SAME `feat/v1-native-winforms` / DRAFT PR #4. Current orientation head `cebc01c84027e0890aa828400078c84d38bdcdf3`, binary version `0.4.6.0`. Exact-head workflow `35679569323` succeeded: core 88/88, screensaver/idle-lock 44/44. Current `dev-latest` targets that exact source head; EXE SHA-256 `94c57bf93a82f1b084583febc55093290fb49a2a9b5dc33a1d94c2fbb60a2452`.

Current architecture now keeps the main app in the signed-in user and uses a bounded elevated machine-inactivity broker after one explicit UAC approval. Intended behavior: UAC Yes -> 900 -> 0 -> Protected; Stop/Exit -> broker restores 900 without a second UAC. UAC No is latched so it must not nag repeatedly; requested idle-lock protection is shown as an Indeterminate/grey tri-state checkbox until an explicit Retry or new Start attempt.

Owner-observed evidence already includes native endpoint launch, basic Start/Stop/Exit, duplicate notice, AC/DC lid behavior, normal restart blocker screen, exact clean restore of machine inactivity/screensaver/SleepDc, and 0.4.3 main-user data path `C:\Users\vincentius\AppData\Local\WindowsNoSleep`. Do not require those tests again merely because 0.4.6 changed the UAC/broker/UI path.

Pending physical changed-path acceptance: install 0.4.6 via existing updater; UAC No -> Degraded + grey/Indeterminate + no prompt loop; explicit Retry -> Yes -> Protected; Stop with no second UAC and verified 900 restore; Start -> Yes -> Exit with no second UAC and verified restore. Then hard-kill ONLY the non-elevated main process to prove broker auto-restore, then Start with Windows reboot/login acceptance. Stable `v1.0.0`, merge and final release labels remain blocked until this is resolved.

Do not revive the PowerShell lane, create another branch, disable security, bypass UAC, fight MDM/domain policy, or ask the owner to resume ZIP/extract loops. Existing binary delivery remains `Update Windows No Sleep.cmd` -> `artifacts\local-current\WindowsNoSleep.exe`.

---

## Historical progress retained below


## Current status — 2026-09-17

Phase: **P2 — EDR remediation / native compiled pilot validation**.

GitHub is the source of truth.

### Owner-approved architecture pivot

Issue #3 established a protected-endpoint compatibility failure for the PowerShell-first runtime/recovery path. The owner has approved the replacement direction recorded in `docs/NATIVE_RUNTIME_DECISION.md` on `main`.

The approved native direction is:

- conventional compiled C# WinForms application;
- .NET Framework 4.8;
- portable x64 `WindowsNoSleep.exe`;
- normal non-elevated manifest;
- no PowerShell/CMD/script-host child process in normal operation;
- no embedded/extracted script payload;
- no obfuscation, runtime download, EDR bypass or automatic elevation;
- no signing purchase required for the first pilot.

Approved recovery direction for the later mutating build:

1. durable recovery journal written before any temporary policy mutation;
2. Windows Application Recovery and Restart (`RegisterApplicationRecoveryCallback` / `RegisterApplicationRestart`) for conventional crash/hang recovery where Windows invokes it;
3. restore-before-protect on every normal launch if a journal remains pending.

ARR is best-effort and is not treated as a guarantee for force-kill, EDR termination, power loss or kernel failure. No `RunOnce`, scheduled task, service or hidden recovery helper is currently approved for the native V1 design.

### Implementation lanes

- **Active lane:** `feat/v1-native-winforms` / DRAFT PR #4.
- **Superseded lane:** `feat/v1-portable-tray` / closed DRAFT PR #2. It remains reference/history only.
- Issue #3 remains open.
- Old local Dispatch 004 remains cancelled/HOLD and must not be executed.

### Native Stage B pilot

Exact current native pilot head: `46d99c00c276266b5e53be31fa19eedebadc9990`.

Implemented at that head:

- `native/WindowsNoSleep/WindowsNoSleep.csproj` — x64 .NET Framework 4.8 WinForms executable;
- immediate direct `PowerCreateRequest` / `PowerSetRequest(PowerRequestSystemRequired)` lease;
- tray icon;
- small Settings/status window;
- Start/Stop Protection;
- Exit cleanup;
- `--self-test` path that acquires/releases only the SystemRequired lease;
- ordinary `asInvoker` manifest;
- CI Release build, exact package artifact and SHA-256 recording.

The pilot deliberately has **no**:

- lid-action mutation;
- AC/DC sleep-timeout mutation;
- registry startup entry;
- `RunOnce` recovery;
- recovery journal (not needed yet because the pilot makes no persistent policy mutation);
- shutdown guard;
- Battery Safety controller;
- installer;
- signing requirement;
- AV/EDR exclusion or bypass.

### Hosted evidence for the native pilot

GitHub Actions run `35203872675` on exact head `46d99c00c276266b5e53be31fa19eedebadc9990` is GREEN:

- x64 Release build: PASS, 0 warnings / 0 errors;
- exact compiled EXE `--self-test`: PASS;
- package creation: PASS;
- artifact upload: PASS.

Published workflow artifact:

- artifact name: `WindowsNoSleep-native-pilot`;
- artifact ID: `10489380366`;
- uploaded artifact digest: `sha256:41bdebfe7c32a831e3840cc4fb36695c8f843d569784dbf5d16d1844d1395a9f`;
- distributable nested ZIP SHA-256: `758dbf9a68a8ca830332feebe7a57722cfa69eb512957590f1aa81627f731b87`;
- `WindowsNoSleep.exe` SHA-256: `4EC31D00B718A541021773590423A9385895FBA812964F3912C2983C55F2FB51`;
- signing status: **UNSIGNED PILOT**.

This is hosted build/runtime evidence only. It is **not** `EDR_VERIFIED` and does not inherit physical acceptance labels from the old PowerShell build.

### Issue #3 safety findings that remain authoritative

- The original EDR report quarantined multiple PowerShell/source files plus `WindowsNoSleepRecovery` startup state. Root cause attribution to any single behavior is still unproven.
- The old `tests/WindowsIntegrationTests.ps1` is not a safe generic laptop integration command because it can force-kill the real production app and remove transient runtime data without first proving restoration on a battery-equipped machine.
- Do not rerun the old quarantined PowerShell path on the affected endpoint.
- Do not disable or bypass endpoint security or add broad exclusions merely to obtain a pass.

### Previously verified physical evidence — reference only for the new binary

The old PowerShell build established useful product/platform facts:

- `LOCAL_READ_ONLY_VERIFIED` — Windows 11 25H2 / Modern Standby S0 baseline;
- `LOCAL_POLICY_TRANSACTION_VERIFIED` — real `SleepIdle DC 1200 -> 0 -> 1200` exact restore;
- `LID_CLOSED_AC_EXTERNAL_DISPLAY_VERIFIED` — lid closed on AC with external display attached; ~1 Hz workload continued with max gap ~1.046 s.

Those facts inform the port, but they do **not** certify PR #4 or the new EXE.

### Local executor status

**WAIT until a new native-pilot dispatch is explicitly issued.**

The next physical step should use the exact CI artifact above on an approved protected endpoint with normal security policy, no exclusions, no admin elevation, and no power-policy mutation. A security detection immediately stops the trial.

If the exact native pilot is accepted, continue porting the remaining V1 features in the same branch/PR #4. Do not spawn a competing rewrite.

### Remaining gates

- exact unsigned native pilot accepted on the agreed protected endpoint;
- Battery Safety port;
- supported shutdown/restart guard port;
- durable recovery journal + ARR implementation and independent safety review;
- bounded real policy apply/restore on the native build;
- crash/next-launch recovery proof;
- `BATTERY_VERIFIED` on the native build;
- `HEADLESS_VERIFIED` on the native build;
- longer Modern Standby/overnight soak;
- final protected-endpoint package acceptance and any later signing/deployment decision;
- independent release review before native PR is ready/merged.


### Native pilot local dispatch

`docs/LOCAL_NATIVE_PILOT_DISPATCH_001.md` is now **AUTHORIZED** for one non-mutating protected-endpoint compatibility test using the exact CI artifact from run `35203872675` / source head `46d99c00c276266b5e53be31fa19eedebadc9990`.

The test keeps normal endpoint security enabled, requires the exact EXE SHA-256 `4EC31D00B718A541021773590423A9385895FBA812964F3912C2983C55F2FB51`, and exercises only tray launch, Protected -> Stopped -> Protected, and Exit. It authorizes no power-policy mutation, registry persistence, elevation, security exclusion, battery/lid test, or recovery test.

Any warning/block/quarantine immediately stops the trial; do not rerun or whitelist.



### Successor Control Tower handoff — 2026-09-21

Durable full successor handoff:

`docs/CONTROL_TOWER_HANDOFF_20260921.md`

Read it through this exact sentinel before claiming full handoff consumption:

`END_OF_CONTROL_TOWER_HANDOFF key=WNS-CT-20260921-NATIVE-PILOT-PENDING-V1 sections=18`

Current handoff posture: **native pilot physical protected-endpoint test is still PENDING, not PASS/FAIL.**

The owner had only begun local artifact/path preparation and had not yet returned a matching EXE hash or runtime/EDR result. Continue `docs/LOCAL_NATIVE_PILOT_DISPATCH_001.md`; do not restart architecture work or revive the PowerShell lane.
