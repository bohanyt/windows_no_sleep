# Windows No Sleep — Control Tower Successor Handoff

Status: **ACTIVE SUCCESSOR HANDOFF**  
Date: 2026-09-23  
Repository: `bohanyt/windows_no_sleep`  
Owner: Bohan / `bohanyt`  
Role handed off: SAME continuing Control Tower for Windows No Sleep

## 1. Successor operating rule

GitHub is the source of truth. This handoff replaces the 2026-09-21 handoff for current orientation.

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
10. DRAFT PR #4 metadata, exact head and exact-head CI
11. current `dev-latest` release metadata

Do not continue from chat memory without fresh-checking GitHub. SHAs below are orientation only.

Keep staffing small: one Control Tower, one implementation lane, physical Windows operator only when endpoint evidence is actually needed. Do not create a competing branch or rewrite.

## 2. Current product goal

Portable Windows utility that keeps computer/workloads running while still allowing the display to dim/off.

Target UX:

`launch -> Protection starts -> tray app -> Settings -> reversible Stop/Exit`

Current V1 scope now includes:

- SystemRequired awake request;
- ordinary screensaver prevention;
- local Machine inactivity auto-lock suppression when administrator approval is available;
- lid-close protection;
- DC sleep/hibernate timeout protection;
- Battery Safety;
- normal shutdown/restart blocker;
- durable recovery and restore-before-protect;
- optional Start with Windows.

Safety remains higher priority than staying awake.

## 3. Active / superseded lanes

Active implementation:

- branch: `feat/v1-native-winforms`
- DRAFT PR: #4
- PR remains OPEN/DRAFT, not accepted for merge.

Current orientation source head at handoff creation:

`cebc01c84027e0890aa828400078c84d38bdcdf3`

Superseded:

- old PowerShell PR #2 is CLOSED/reference-only;
- old PowerShell Dispatch 004 remains cancelled/HOLD;
- do not revive the PowerShell implementation as the production lane.

No new branch is needed.

## 4. Current delivered development build

Current rolling prerelease:

- tag: `dev-latest`
- target: `cebc01c84027e0890aa828400078c84d38bdcdf3`
- binary version: `0.4.6.0`
- `WindowsNoSleep.exe` SHA-256:
  `94c57bf93a82f1b084583febc55093290fb49a2a9b5dc33a1d94c2fbb60a2452`
- unsigned development build.

Exact-head workflow:

- run: `35679569323`
- job: `106593369912`
- conclusion: SUCCESS
- core fake-provider suite: `TOTAL=88 PASSED=88 FAILED=0`
- screensaver/idle-lock suite: `SCREENSAVER_TOTAL=44 PASSED=44 FAILED=0`
- package + rolling dev publication: PASS.

Do not confuse hosted regressions with physical endpoint acceptance.

## 5. Implementation state from 0.4.0 through 0.4.6

Bundled native V1 0.4 introduced:

- direct SystemRequired awake request, display off allowed;
- normal shutdown/restart blocker;
- Battery Safety base 15% with higher readable Windows critical threshold +5 and hysteresis;
- temporary LidAction AC/DC and DC SleepIdle/HibernateIdle writes only when needed;
- durable write-ahead power journal and exact restore;
- ARR best-effort recovery + restore-before-protect;
- optional HKCU Start with Windows;
- tray/settings/diagnostics, branded icon, duplicate-launch notice;
- rolling updater path.

0.4.1 added default-on ordinary screensaver suppression and truthful lock diagnostics.

0.4.2 added reversible local `InactivityTimeoutSecs` 900 -> 0 -> 900 handling when elevated.

0.4.3 corrected the account model: the main app remains in the signed-in user (`vincentius` in owner testing); only the privileged machine-policy operation elevates.

0.4.4 latched a denied administrator request so UAC is not supposed to repeatedly nag until an explicit retry/start attempt.

0.4.5 introduced the elevated machine-inactivity broker model: one UAC approval at protection start, then broker-assisted silent restore on Stop/Exit; the broker also watches for the main process disappearing and is intended to restore after a hard kill.

0.4.6 changed the screensaver/idle-lock checkbox to tri-state semantics:
- Checked = requested and fully active;
- Indeterminate/grey = requested but administrator approval/idle-lock protection is pending;
- Unchecked = user intentionally disabled the feature.

## 6. Current privilege / broker contract

The main WinForms application keeps the signed-in user's context and data directory.

Normal intended flow:

`Start -> one UAC approval -> local inactivity 900 -> 0 -> Protected`

The elevated broker remains hidden only to service the bounded local machine inactivity transaction.

Normal Stop/Exit intended flow:

`Stop/Exit -> broker restores 0 -> 900 -> exits -> NO second UAC`

If UAC is denied:

- no automatic UAC spam;
- main protection remains running where possible;
- overall state becomes Degraded because local auto-lock remains;
- requested checkbox is grey/Indeterminate;
- `Retry administrator protection` is the explicit retry path;
- Stop -> Start is also an explicit new attempt.

This bounded broker decision is newer owner-approved product direction and supersedes older generic wording that no helper could ever exist. It does NOT authorize a service, scheduled-task persistence, security bypass, silent UAC bypass, or enterprise-policy fighting.

## 7. Physical evidence already obtained on the owner's Windows laptop

Treat these as owner-observed endpoint evidence; do not upgrade beyond what was actually seen.

Observed:

- native unsigned EXE launched on the protected laptop without the earlier PowerShell-style security warning;
- Start -> Protected, Stop -> Stopped, Start -> Protected, tray Exit cleanup worked on earlier native builds;
- duplicate-launch countdown notice worked;
- branded icon/tray UI worked;
- owner reported AC clamshell behavior working with internal panel off / HDMI continuing;
- owner reported DC lid behavior working;
- 0.4.2/0.4.3 local inactivity value was observed as original 900 and temporary 0;
- normal Windows Restart attempt showed Windows No Sleep as a visible blocker with `Restart anyway / Cancel`; treat normal restart guard as owner-observed PASS;
- clean Stop restoration was explicitly observed:
  - machine inactivity restored `900 -> 900`;
  - screensaver restored;
  - SleepDc restored `1200 -> 1200`;
  - `RESTORE_VERIFIED`;
  - state `Stopped`;
- 0.4.3 main-app context was explicitly confirmed:
  `Data: C:\Users\vincentius\AppData\Local\WindowsNoSleep`
  with `State: Protected`;
- 0.4.3 logged:
  `MACHINE_INACTIVITY_ACTIVE originalSeconds=900 temporary=0`
  and `machineInactivityOverridden=True`.

The owner explicitly told Control Tower to treat the idle-lock behavior as provisionally acceptable rather than stopping work for another >15 minute idle wait.

## 8. Evidence that is still NOT proven

Do not invent PASS for any of these:

- 0.4.6 tri-state UI has not yet been physically confirmed after updating;
- denied-UAC no-spam behavior has not yet been physically confirmed on 0.4.6;
- 0.4.5/0.4.6 broker silent Stop restore has not yet been physically confirmed;
- broker silent tray Exit restore has not yet been physically confirmed;
- hard Task Manager kill with broker automatic 900 restore has not yet been physically confirmed;
- Start with Windows has not yet been proven across a real logout/reboot/login cycle;
- physical Battery Safety threshold transition has not been proven by intentionally reaching 15%, and should not be forced unsafely;
- no independent final release review has occurred;
- stable `v1.0.0` has NOT been published;
- PR #4 has NOT been merged;
- final `EDR_VERIFIED` / production-ready label is not established.

Also: the owner did not complete an objective >15-minute idle witness after the newest fixes; they explicitly allowed provisional acceptance so work could continue.

## 9. Owner delivery workflow — do not regress it

Owner strongly dislikes repeated ZIP/extract/manual folder loops.

Local repository used:

`C:\Users\vincentius\Documents\ISTW IT Projects\windows_no_sleep-local-verify`

Existing updater:

`Update Windows No Sleep.cmd`

Current installed dev location:

`artifacts\local-current\WindowsNoSleep.exe`

Normal dev update flow:

1. Exit the currently running app from tray.
2. Double-click existing `Update Windows No Sleep.cmd`.
3. Updater downloads `dev-latest`, verifies/stages assets and launches the same local-current executable.

Do NOT ask for a new clone, new folder, git pull, manual ZIP extraction or artifact shuffling for normal binary updates.

## 10. Immediate physical acceptance — denied UAC / tri-state

This is the next bounded owner test once 0.4.6 is installed.

Test only the changed path:

1. Start Protection / launch with local inactivity policy still 900.
2. When UAC appears, click **No** once.
3. Expected:
   - app remains alive;
   - state becomes Degraded;
   - ordinary/basic awake protection continues where possible;
   - screensaver/idle-lock checkbox becomes grey/Indeterminate, not automatically unchecked;
   - `Retry administrator protection` is visible;
   - UAC does NOT reappear automatically.
4. Wait 10–20 seconds only to prove no prompt loop.
5. Click `Retry administrator protection`.
6. UAC may appear once because retry is explicit.
7. Click Yes.
8. Expected:
   - local 900 -> 0;
   - state -> Protected;
   - checkbox normal Checked.

If UAC reappears by itself after No, that is a bug. Fix source; do not tell the owner it is expected.

## 11. Immediate physical acceptance — Stop and Exit with no second UAC

After the previous path is Protected:

### Stop

- click `Stop Protection`;
- expected: no new UAC;
- expected machine inactivity restore to 900;
- state -> Stopped;
- recovery pending should clear after verified restore.

Desired log evidence includes:

`MACHINE_INACTIVITY_RESTORE_VERIFIED original=900 after=900`

### Exit

- Start Protection again and approve the one initial UAC;
- reach Protected;
- right-click tray -> Exit;
- expected: no new UAC;
- app exits;
- broker restores original 900 and exits.

Do not repeat lid/DC/restart-guard testing merely because this broker/UI patch changed.

## 12. Hard-crash broker acceptance after Stop/Exit PASS

Only after section 11 passes:

1. Start and reach Protected.
2. In Task Manager identify the non-elevated main `WindowsNoSleep.exe` belonging to the signed-in user.
3. End Task ONLY the main process. Do not intentionally kill the elevated broker.
4. Expected broker behavior:
   - sees main process disappear;
   - restores `InactivityTimeoutSecs` to original 900;
   - exits.
5. Relaunch app normally.
6. Recovery must be clean; then a new explicit Start/UAC can apply 900 -> 0 again.

The successor should give the owner a precise Task Manager identification sequence before this test. Do not make them guess which process is the broker.

## 13. Start with Windows acceptance

Only after broker restore behavior is proven.

Current UI option is opt-in:

`Start with Windows (after I sign in)`

Required acceptance:

- enable once under the signed-in user;
- Exit cleanly;
- reboot/login as that same user;
- exactly one main instance starts;
- because local machine inactivity needs admin permission, UAC may still be required after sign-in; do not claim silent autostart elevation;
- after approval, Protection should reach Protected.

Do not introduce UAC-bypass tricks, elevated HKCU Run abuse, service/task persistence or credential storage merely to make startup silent.

If the owner later requires fully unattended privileged startup, treat that as a new architecture decision and review separately before implementation.

## 14. Remaining V1 / safety campaign

Already owner-observed and should not be needlessly repeated:
- native UI/tray basics;
- lid behavior on AC/DC;
- normal restart blocker;
- clean restore path.

Still useful before stable:
- changed UAC/tri-state/broker tests in sections 10–12;
- Start with Windows reboot/login;
- one final Diagnostics capture;
- optional safe longer soak if owner wants it.

Battery Safety remains primarily regression-tested unless a safe real threshold transition occurs naturally. Do not deliberately drain the laptop into an unsafe battery state just to create a label.

## 15. Stable release plan

Current `dev-latest` is prerelease/development only.

After the final changed-path physical acceptance:

1. fresh-check PR #4 exact head and all CI;
2. reconcile main authority docs with final native architecture;
3. run one independent release/source review focused on restoration, broker lifecycle and stable packaging;
4. decide whether PR #4 is ready to merge;
5. publish a stable portable `v1.0.0` only after explicit Control Tower acceptance;
6. stable user update behavior should follow stable releases only and ignore `dev-latest` prerelease.

Do not publish stable merely because CI is green.

## 16. Safety / forbidden drift

Never authorize:

- disabling EDR/AV to obtain a pass;
- exclusions/whitelisting as a substitute for compatibility;
- password bypass or auto-unlock;
- fake keyboard/mouse keepalive as the primary mechanism;
- fighting domain/MDM lock policy in a loop;
- changing Windows critical-battery action;
- `powercfg /hibernate off`;
- disabling Windows Update/Medic/BITS;
- changing power-button action;
- silently bypassing UAC;
- broad persistent service/task creation without a new explicit architecture decision.

Manual Win+L, Dynamic Lock/presence sensing, enterprise policy, forced shutdown, thermal and critical-battery safety remain authoritative platform boundaries.

## 17. Known documentation drift / supersessions

Older main docs still contain pre-bundle/pilot language. Use authority order and this handoff to avoid reviving obsolete sequencing.

Important supersessions:

- earlier pilot-only sequencing was superseded by the owner's 2026-09-21 instruction to bundle all remaining V1 features before one consolidated acceptance campaign;
- earlier `Restart as administrator` whole-app design was superseded by 0.4.3 user-context separation;
- earlier generic no-helper wording is superseded only for the bounded 0.4.5 machine-inactivity broker described above;
- old `PROGRESS.md` pilot state is superseded by the new 2026-09-23 current-status block and this handoff;
- old handoff `WNS-CT-20260921-NATIVE-PILOT-PENDING-V1` is historical only.

GitHub Issue #1 remains the master product/work queue. Issue #3 remains historical/security evidence and should not be closed casually.

## 18. Exact next action / successor posture

At handoff creation:

- main before this handoff write: `fefb0051edeed3a5fc9ac0da7c69e9c9bcbb79f1`;
- active source branch head: `cebc01c84027e0890aa828400078c84d38bdcdf3`;
- DRAFT PR #4: active, not merged;
- exact-head CI `35679569323`: SUCCESS;
- current `dev-latest`: exact source head above;
- build: `0.4.6.0`;
- next action is **physical changed-path acceptance of UAC No -> tri-state/no-spam -> Retry/Yes -> Stop no second UAC -> Exit no second UAC**.

Do not ask the owner to restart earlier lid/DC/restart tests. Continue from this point.

If any changed-path behavior fails, fix it on SAME `feat/v1-native-winforms` / SAME DRAFT PR #4, re-run exact-head CI, update `dev-latest`, and re-test only the affected path.

END_OF_CONTROL_TOWER_HANDOFF key=WNS-CT-20260923-V1-046-UAC-BROKER-PENDING sections=18
