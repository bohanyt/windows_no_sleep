# Windows No Sleep — Control Tower Successor Handoff

Status: **ACTIVE SUCCESSOR HANDOFF**  
Date: 2026-09-25  
Repository: `bohanyt/windows_no_sleep`  
Owner: Bohan / `bohanyt`  
Role handed off: SAME continuing Control Tower for Windows No Sleep

## 1. Successor operating rule

GitHub is the source of truth. This handoff supersedes `docs/CONTROL_TOWER_HANDOFF_20260923.md` for current orientation while preserving older handoffs as history.

FIRST fresh-read, in this order:

1. `README.md`
2. `docs/PLAN_V1.md`
3. `docs/TEST_PLAN.md`
4. `docs/CONTROL_TOWER.md`
5. `docs/NATIVE_RUNTIME_DECISION.md`
6. `PROGRESS.md`
7. this file in full through its sentinel
8. latest Issue #1 comments
9. latest Issue #3 comments
10. DRAFT PR #4 metadata, exact head, mergeability and exact-head CI
11. current `dev-latest` release metadata

Do not continue from chat memory without fresh-checking GitHub. SHAs below are orientation only.

Keep staffing small: one Control Tower, one implementation lane, one physical Windows operator only when endpoint evidence is actually needed, plus one independent release reviewer near stable. Do not create a competing branch or rewrite.

## 2. Product goal and current V1 behavior

Windows No Sleep is a portable native Windows utility intended to keep the computer/workloads running while maintaining safety and restoring every temporary setting it owns.

Current native V1 scope includes:

- `PowerRequestSystemRequired`;
- ordinary screensaver suppression;
- bounded local Machine inactivity override with explicit administrator approval;
- elevated machine-inactivity broker for silent restore after approval;
- temporary lid AC/DC protection;
- temporary DC SleepIdle/HibernateIdle protection where applicable;
- Battery Safety;
- normal shutdown/restart blocker;
- durable recovery / restore-before-protect;
- opt-in per-user Start with Windows;
- Modern Standby DC-specific transient `PowerRequestDisplayRequired` in 0.4.7.

Important 0.4.7 behavior change: on qualifying Modern Standby battery/DC protection, the display is intentionally kept logically on so Windows does not enter the target laptop's display-idle Modern Standby path. On AC, the normal display-off-allowed behavior remains.

Safety remains higher priority than staying awake.

## 3. Active implementation lane

Active implementation remains:

- branch: `feat/v1-native-winforms`
- DRAFT PR: #4
- PR state: OPEN / DRAFT / unmerged
- exact current source head at handoff creation:
  `ab1e0f1035c553e6474b2866637191d1406a9cfb`
- binary version: `0.4.7.0`

Do not create a new implementation branch.

Old PowerShell PR #2 remains CLOSED/reference-only. Old PowerShell Dispatch 004 remains cancelled/HOLD and must not be revived.

## 4. Current exact-head CI and delivered build

Exact authoritative workflow for 0.4.7:

- run: `36085094582`
- job: `107915092623`
- event: push
- exact head: `ab1e0f1035c553e6474b2866637191d1406a9cfb`
- conclusion: **SUCCESS**

Verified successful steps include:

- Windows SDK ABI check;
- Release x64 build;
- non-mutating native PowerRequest self-test;
- regression suite;
- regression evidence upload;
- package creation;
- exact application artifact upload;
- rolling `dev-latest` publication.

Local pre-push proof reported:

- core regression: `103/103 PASS`;
- screensaver/idle-lock regression: `44/44 PASS`;
- FileVersion/ProductVersion: `0.4.7.0`.

The authoritative GitHub workflow supersedes the local machine's missing ABI/compiler/reference-assembly limitations.

## 5. Current dev-latest identity

Current rolling prerelease:

- release ID: `396226381`
- tag: `dev-latest`
- target: `ab1e0f1035c553e6474b2866637191d1406a9cfb`
- prerelease: true
- `WindowsNoSleep.exe` size: `151040` bytes
- EXE SHA-256:
  `7a62745e408792a0c1c3d4e863e0f46a3af7fc9c18e53b567d0be87fbd397e74`

Asset set remains:

- `WindowsNoSleep.exe`
- `WindowsNoSleep.exe.config`
- `README.txt`
- `SHA256SUMS.txt`
- `BUILD_SHA.txt`

Normal owner update path remains:

`Update Windows No Sleep.cmd` -> `artifacts\local-current\WindowsNoSleep.exe`

No new clone, ZIP loop or folder reorganization should be requested.

## 6. Why 0.4.7 exists — Modern Standby DC root cause

The owner reported that 0.4.6 truly reached the Windows lock/password screen on battery/DC.

Local read-only investigation established that this was NOT:

- a stale build;
- ordinary screensaver re-enable;
- machine inactivity 900 restore;
- UAC/broker failure;
- DC SleepIdle failure;
- source/power-plan drift.

The exact 0.4.6 binary was confirmed by version/hash/build SHA.

Physical/event-log evidence showed:

- machine is S0 Low Power Idle / Modern Standby only;
- DC display timeout is 600 seconds;
- AC display timeout is Never;
- app remained Protected;
- ordinary screensaver suppression remained active;
- `InactivityTimeoutSecs=0`;
- DC SleepIdle was already 0;
- every observed battery lock aligned with Kernel-Power 506: entering Modern Standby, Reason: Idle Timeout;
- two events occurred at about 606 seconds after entering DC;
- heartbeat continuity showed workloads remained active rather than a conventional suspend path.

CT classified this as a V1 coverage/design gap: on this target, display-off is the entry into Modern Standby, which then produces the normal session lock/password behavior.

Root-cause authority: Issue #1 comment `5825180542`.

## 7. 0.4.7 correction

Correction packet: Issue #1 comment `5825228643`  
Packet key: `WNS-047-MS-DC-DISPLAY-20260925-V1`

Implemented commit:

`ab1e0f1035c553e6474b2866637191d1406a9cfb`

The correction adds a separate transient `PowerRequestDisplayRequired` lease only while all of these are true:

- Protection wanted/running;
- SystemRequired active;
- power state readable;
- Modern Standby capable;
- battery present;
- definitely DC;
- Protect on battery enabled;
- outside Battery Safety;
- not suspended/terminal/stopped.

Lifecycle:

- Start already on qualifying DC -> SystemRequired + DisplayRequired;
- live AC -> DC -> acquire DisplayRequired without restarting protection;
- repeated DC polling is idempotent;
- DC -> AC -> release DisplayRequired while keeping SystemRequired;
- Battery Safety / Stop / Suspend / generic cleanup / crash recovery -> release;
- Resume re-evaluates;
- acquisition failure -> truthful Degraded while retaining unrelated safe protection;
- failure is latched to avoid 2-second retry/log spam;
- leaving the qualifying state/new Start allows a meaningful retry.

No display-timeout registry/power-plan mutation was added. No password/security policy change. No fake input. No new recovery-journal key. No UAC/broker redesign.

CT diff review: Issue #1 comment `5825497403` -> `PUSH_OK`.

## 8. Current physical 0.4.7 evidence already observed

Owner updated to 0.4.7 and supplied runtime log evidence.

Observed clean previous-session restoration:

- `MACHINE_INACTIVITY_RESTORE_VERIFIED original=900 after=900`
- `SCREENSAVER_RESTORE_VERIFIED original=True after=True`
- `RESTORE_VALUE SleepDc original=1200 after=1200`
- `RESTORE_VERIFIED ...`
- `STATE Stopped`
- `EXIT cleanup completed; recoveryPending=False`

Observed new exact candidate launch:

`START version=0.4.7.0 build=ab1e0f1035c553e6474b2866637191d1406a9cfb`

Observed normal protection activation:

- `MACHINE_INACTIVITY_ACTIVE originalSeconds=900 temporary=0`
- `SCREENSAVER_ACTIVE ... machineInactivityOverridden=True`
- `POLICY_BEFORE SleepDc original=1200 temporary=0`
- `POLICY_ACTIVE ... changed=1`
- `STATE Protected`

After unplugging AC, the new path was physically observed:

`DISPLAY_REQUIRED_ACTIVE reason=modern_standby_dc`

This proves the intended AC->DC DisplayRequired transition occurs on the owner endpoint.

It does NOT yet prove the full >600-second lock-prevention outcome.

## 9. Immediate next action — focused 0.4.7 DC idle witness

This is the first action for the successor unless the owner has already returned the result.

Do only this focused gate:

1. exact 0.4.7 build above installed;
2. begin Protected on AC;
3. adequate battery;
4. lid OPEN;
5. Protect on battery enabled;
6. unplug charger;
7. verify Diagnostics/log shows DisplayRequired active;
8. leave keyboard/mouse untouched beyond the old 600-second display timeout; target 11–12 minutes;
9. PASS if the prior Windows lock/password path does NOT recur;
10. reconnect AC;
11. verify DisplayRequired releases, ideally:
    `DISPLAY_REQUIRED_RELEASED reason=ac`
12. verify main protection remains Protected/SystemRequired-active.

If the test fails, preserve the exact timestamp, app log and corresponding Windows Kernel-Power/session event evidence. Do not improvise security/power-policy changes. Continue correction on SAME branch / SAME PR #4.

Do not repeat UAC-No, lid-close, restart blocker or previously accepted basic tests solely because of this correction.

## 10. Earlier physical evidence that should not be needlessly repeated

Owner-observed evidence from the current native lineage includes:

- native EXE/tray/settings launch;
- branded UI and duplicate-launch notice;
- Start/Stop/Exit basics on earlier native builds;
- AC closed-lid workload continuity;
- DC lid behavior owner-observed;
- one later ~30-minute closed-lid continuity observation with Parsec host/workload remaining usable afterward;
- normal Windows Restart blocker screen;
- clean machine inactivity/screensaver/SleepDc restoration;
- 0.4.3+ main-app data path in the signed-in user;
- UAC-No visual behavior on 0.4.6:
  - Degraded;
  - machine inactivity warning 900 seconds;
  - tri-state/Indeterminate requested checkbox;
  - Retry administrator protection visible;
- normal Stop from Protected with no second UAC and original 900 restored was owner-reported as already proven;
- Start with Windows survived reboot/login and showed the expected UAC for the bounded privileged operation, after which Protection could become active;
- local diagnostic inspection observed one non-elevated main plus one elevated broker, not a duplicate main.

Do not inflate these beyond what was observed. In particular, a Parsec session being usable afterward does not prove its transport never briefly reconnected.

## 11. Broker / UAC architecture and remaining physical broker gate

Current bounded machine-inactivity contract:

`Start -> one explicit UAC -> 900 -> 0 -> Protected`

Normal Stop/Exit intent:

`restore 0 -> 900 through already-elevated broker -> no second UAC`

Broker also watches the non-elevated main process and is intended to restore 900 if that main disappears.

Prepared hard-kill acceptance packet already exists:

Issue #1 comment `5788800106`

Do NOT run hard-kill until the current 0.4.7 focused DC gate is PASS.

After DC PASS, if still unproven, use the prepared packet to:

- identify main vs broker by Task Manager Details / command line / elevation;
- End Task ONLY the non-elevated main;
- never End process tree;
- verify `InactivityTimeoutSecs` is restored to 900 before relaunch;
- verify broker exits itself.

The hard-kill broker test remains a stable gate unless later evidence already satisfies it.

## 12. Source-review findings retained for pre-stable review

AFK/source audit authority: Issue #1 comment `5788790946`.

Retained findings:

**S1 — denial latch scope.**  
`ProtectionController.Stop()` clears the administrator-denial latch. Option changes use `ChangeOptions -> Stop -> Start`, so changing another protection option after UAC No can permit a new UAC request. This is not timer spam, but it is looser than the simple Retry/new-Start wording. Independent reviewer must adjudicate before stable.

**S2 — hard-kill parent identity.**  
Broker watcher identifies parent by PID. Theoretical fast PID reuse could delay auto-restore. Reviewer should decide whether PID + creation-time/process-handle identity is required for stable.

**S3 — broker event ACL.**  
Random Local named broker events use `WorldSid FullControl`. Nonce reduces discoverability, but this is broader than least privilege. Reviewer should adjudicate.

0.4.7 adds no new issue to these findings; it only adds DisplayRequired lifecycle.

## 13. PR #4 dirty state / reconciliation plan

At handoff creation:

- PR #4: OPEN / DRAFT / unmerged
- exact head: `ab1e0f1035c553e6474b2866637191d1406a9cfb`
- GitHub reports `mergeable=false`, `mergeable_state=dirty`.

Prior audit established that main changes since PR base overlap the implementation PR materially only in `PROGRESS.md`; the C# source, workflow, updater and native packaging were not overlapped by the newer main handoff commits.

Do NOT resolve this conflict during physical acceptance.

After all required physical gates pass:

1. fresh-check the actual conflict set again;
2. preserve current main authority/current-status blocks;
3. manually carry forward useful candidate progress evidence;
4. do not resurrect old PowerShell sequencing;
5. ensure conflict resolution contains no hidden source change;
6. keep historical handoffs as history.

## 14. Release-prep gaps before stable

AFK release audit: Issue #1 comment `5788790946`.

Known pre-stable gaps:

**R1 — updater integrity.**  
`Update Windows No Sleep.cmd` downloads `SHA256SUMS.txt` but does not currently verify the downloaded EXE hash before replacing `local-current`.

**R2 — updater channel.**  
Updater is hard-coded to `dev-latest`. Stable-channel semantics are not implemented.

**R3 — stable publication process.**  
Current workflow replaces rolling `dev-latest`; no final stable workflow/process is yet established.

**R4 — stable metadata.**  
Current development binary is 0.4.7.0 and package/manifest text still contains development/pilot-era wording in places. A stable `v1.0.0` rebuild changes the exact binary/hash, so physical evidence vs rebuilt metadata must be represented truthfully.

**R5 — signing/EDR.**  
Current build remains unsigned by design. Do not claim `EDR_VERIFIED` for a final stable package unless that exact package was actually observed under intended endpoint security.

Do not publish stable merely because CI and the focused DC test are green.

## 15. Documentation drift that must be reconciled before stable

Known stale/current-conflicting docs include:

- main `README.md` — old planning/PowerShell-first wording;
- `docs/PLAN_V1.md` — old PowerShell packaging lane;
- `docs/TEST_PLAN.md` — old PowerShell packaging/EDR test language;
- `docs/CONTROL_TOWER.md` — old preferred branch/current-phase wording;
- `docs/NATIVE_RUNTIME_DECISION.md` — older generic no-hidden-helper statement, superseded only for the bounded machine-inactivity broker;
- `docs/NATIVE_V1_ACCEPTANCE.md` — still contains older generic wording that no helper survives main-process death, stale for the machine-inactivity broker;
- PR #4 title/body — still primarily describes bundled 0.4 and does not fully summarize 0.4.1–0.4.7 evolution;
- `PROGRESS.md` — main must stay authoritative after reconciliation.

Historical documents may remain if clearly labeled historical.

Do not rewrite all docs before the physical gate; do it after the product behavior is accepted so documentation reflects the final candidate.

## 16. Independent release review

Prepared reviewer packet exists:

Issue #1 comment `5788807289`  
Packet key: `WNS-RR-PREP-20260923-V1`

It was prepared before 0.4.7. Therefore before dispatching, successor CT must update/supplement the review scope to include:

- exact 0.4.7 DisplayRequired predicate;
- AC->DC and DC->AC lifecycle;
- Battery Safety/Stop/Suspend/crash cleanup;
- failure latch / no retry spam;
- physical >600-second DC result;
- exact 0.4.7 workflow/release identity.

Do not dispatch independent release review until:

- focused 0.4.7 DC gate passes;
- required broker hard-kill gate passes or is explicitly resolved;
- any resulting source correction is exact-head CI green;
- pre-stable packaging/docs candidate is ready for review.

Reviewer remains read-only and has no merge/stable-publish authority.

## 17. Safety / forbidden drift

Never authorize:

- disabling EDR/AV to obtain a pass;
- broad exclusions/allowlisting as a substitute for compatibility;
- password bypass or auto-unlock;
- fake keyboard/mouse keepalive;
- changing Windows password-on-wake to avoid this bug;
- fighting domain/MDM lock policy in a loop;
- changing Windows critical-battery action;
- `powercfg /hibernate off`;
- disabling Windows Update/Medic/BITS;
- changing power-button action;
- silently bypassing UAC;
- broad persistent service/task creation without a new explicit architecture decision;
- deleting recovery journals just to reset a test;
- manually editing machine inactivity to make a test pass.

Manual Win+L, Dynamic Lock/presence sensing, enterprise policy, forced shutdown, thermal/critical-battery safety remain authoritative platform boundaries.

## 18. Exact successor posture

Main before this handoff write:

`e0c6f8c8c6e26e6ebee0ac004a179ce16922ff24`

Implementation orientation:

- SAME branch: `feat/v1-native-winforms`
- DRAFT PR #4
- head: `ab1e0f1035c553e6474b2866637191d1406a9cfb`
- build: `0.4.7.0`
- exact-head workflow `36085094582`: SUCCESS
- `dev-latest` release `396226381`
- EXE SHA-256 `7a62745e408792a0c1c3d4e863e0f46a3af7fc9c18e53b567d0be87fbd397e74`

Current physical posture:

- 0.4.7 exact build installed;
- clean restoration observed;
- Protected state observed;
- AC->DC `DISPLAY_REQUIRED_ACTIVE reason=modern_standby_dc` physically observed;
- **focused idle >600 s result is still pending at handoff creation**.

Successor's immediate job:

1. receive/record the owner's 11–12 minute DC idle result;
2. if PASS, verify AC reconnect releases DisplayRequired;
3. then continue only the still-unproven broker/final gates;
4. then perform bounded pre-stable release/docs reconciliation;
5. then independent release review;
6. only after explicit CT acceptance decide merge and stable `v1.0.0`.

Do not merge PR #4, mark it ready, or publish stable merely because 0.4.7 CI is green.

END_OF_CONTROL_TOWER_HANDOFF key=WNS-CT-20260925-V1-047-DC-PHYSICAL-PENDING sections=18
