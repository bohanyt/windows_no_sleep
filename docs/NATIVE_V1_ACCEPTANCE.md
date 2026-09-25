# Native V1 — consolidated final acceptance

Owner direction (2026-09-21): implement all seven remaining features together and use the existing updater; no per-feature manual ZIP/extract/test loop. Recorded in Issue #1 comment 5754988623. This document replaces per-feature operator dispatch sequencing for this bundled candidate, not the safety/restore requirements.

## Current acceptance record — 2026-09-25

Issue #1 packet `WNS-PRESTABLE-RECONCILE-20260925-V1` accepts the owner's focused physical gates for exact native EXE version `0.4.7.0`, SHA-256 `7a62745e408792a0c1c3d4e863e0f46a3af7fc9c18e53b567d0be87fbd397e74`, built from `ab1e0f1035c553e6474b2866637191d1406a9cfb` by successful workflow `36085094582` and carried by `dev-latest` release `396226381`. Accepted evidence includes Modern Standby DC idle >600 seconds without lock followed by AC DisplayRequired release; broker hard-kill restore from protected 0 to exact original 900 (`0x384`) before relaunch with broker self-exit; previously observed Start with Windows reboot/login and expected UAC (Issue #1 comment 5807529299); Stop through the live broker (5807538189); and earlier lid/restart/basic restoration observations retained in the handoff. These observations apply to the tested owner endpoint and exact candidate, not all Windows/EDR environments.

The current reconciliation packet does not repeat physical tests. PR #4 remains DRAFT/unmerged. Independent review, Issue #3 endpoint-security disposition and stable release decision remain open. The unsigned native EXE is not universally EDR certified. Old PowerShell Dispatch 004 remains prohibited.

The operator campaign below was the historical acceptance plan; the accepted gates above supersede its pending instructions for this packet.

## What is and is not established

Earlier screenshots/reports established the native UI, branded tray, Stop/Start/Exit and duplicate notice. Later focused physical evidence is recorded above. Overnight operation and universal EDR compatibility are not inferred.

Before calling the bundled candidate ready for operator acceptance, its exact-head build and automated tests must finish successfully. The branch remains DRAFT PR #4. CI must never run the normal production app to simulate battery/lid policy on a random runner: `--test-suite` uses fake policy/guard providers and isolated temporary state; `--self-test` owns only a temporary SystemRequired request.

## Single operator campaign (after the complete build)

Before a stable release exists, use `Update Windows No Sleep.cmd dev` only after Exit from all older instances. The default updater channel is latest stable non-prerelease and does not fall back to dev. It validates the staged EXE SHA-256 before replacing `artifacts\local-current`. Keep normal endpoint security enabled. No elevated main app, exclusions, old PowerShell Dispatch 004 or unsafe battery drain.

1. Open Settings from the tray and record Diagnostics build ID, battery/power source, state, enabled options, and any degraded capability. A capability error is not a pass.
2. Start/Stop once and inspect Diagnostics plus `%LOCALAPPDATA%\WindowsNoSleep\last-restore.json`: every attempted value must have before/after evidence and `RESTORE_VERIFIED`. No pending `recovery.json` may be silently erased. This is the restoration checkpoint within the same campaign, before physical lid/DC work.
3. With a harmless independent timestamp workload, safe ventilation and AC connected, start protection, use the two-display setup normally, then briefly close/reopen the lid. Record continuity, not just a green icon. Extend beyond the relevant idle interval only when the short run and restoration are clean. AC display-off is allowed.
4. Test DC only with adequate charge and accessible controls. On Modern Standby hardware, Diagnostics must show the transient display request active while protected on DC; the display stays logically on, which can increase battery use with the lid open. Confirm that it releases on AC and Battery Safety. Observe Battery Safety using a safe temporary application threshold above the current percentage when practical; do not lower Windows critical-battery policy or drain near empty. Confirm awake/restart blockers release and policy originals restore; restore the application's desired 15% threshold afterward. AC resume must respect any pending restore error. The focused DC idle interval physical acceptance follows code review and is performed by the owner.
5. At a convenient time with work saved, test normal Windows shutdown/restart blocking and the explicit Windows override path. Do not manufacture a Windows Update deadline. Enable/disable Start with Windows from Settings and confirm one owner after a normal sign-in. No task/service/RunOnce should appear.
6. Finish with Stop/Exit, prove exact restore, and only then consider a longer display-off/headless/overnight run where the active power source and hardware allow display-off. Keep final outcomes scoped to the tested device, OS image, power source and security product.

No machine shutdown, lid close or DC action is executed by the Control Tower/cloud implementation itself. The owner performs the final physical steps. Report failures and stop further mutations rather than improvising repair.

## Recovery boundaries

Every policy write has a durable attempted record first. Clean Stop/Exit restores exact originals and reads them back. Corrupt, foreign-account/machine or unknown-schema journals are preserved and prevent new writes. A differing external value is treated as a conflict, not blindly overwritten. Active-plan drift stops protection rather than switching the user's plan.

ARR callback registration and restart registration are implemented, but Windows controls whether recovery/restart is offered. The callback has bounded lock acquisition and cancellation pings. A bounded elevated broker is approved only for the explicit-UAC machine-inactivity operation; if the main process disappears it restores the exact original and exits. Other force-kill, EDR termination, power-loss or kernel-failure recovery relies on the preserved next-launch journal, and power loss cannot execute code. A pending journal must never be deleted merely to reset a test.

The local Machine inactivity override writes the machine-wide `HKLM\...\InactivityTimeoutSecs` policy and affects every signed-in user/session. If Windows No Sleep ends without its elevated broker restoring the original value (including power loss, broker termination by security software, an unclean session end, or an elevated main app with no surviving broker), machine-wide inactivity auto-lock can remain disabled across reboot for all users. The recovery record in `%LOCALAPPDATA%` is bound to the original account; another account does not automatically repair it. The same account must relaunch Windows No Sleep and approve the one-shot administrator restore helper to restore the recorded original. Start with Windows defaults to OFF, so restoration may be deferred until that account launches the app. After an abnormal main-app exit, a very rare fast process-ID reuse can defer broker restoration until the unrelated process with that ID exits or the same account relaunches and restores.

Changing any protection option restarts Protection. While local machine-inactivity protection is requested, this can ask for administrator approval again, including after a previous UAC No.

The native V1 supports one power-policy owner across sessions. A second live session cannot own simultaneous policy writes. Cross-account recovery of another user's abandoned journal is not automatic; use the original account/operator rather than guessing settings.

## API references and source review checklist

Primary contracts:
- https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powersetrequest
- https://learn.microsoft.com/en-us/windows/win32/api/powersetting/nf-powersetting-powerwritedcvalueindex
- https://learn.microsoft.com/en-us/windows/win32/api/powrprof/nf-powrprof-powersettingaccesscheck
- https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-system_power_capabilities
- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-shutdownblockreasoncreate
- https://learn.microsoft.com/en-us/windows/win32/shutdown/wm-queryendsession
- https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-registerapplicationrecoverycallback
- https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-registerapplicationrestart

Review the exact four-key allowlist, correct critical-threshold read GUID, 76-byte capability ABI assertions, durable attempted-before-write ordering, rollback on partial failure, preservation of conflicts, battery release ordering, opt-in quoted direct-EXE HKCU startup, no script children/services/RunOnce, and absence of forbidden power/update mutations. Source review and automated tests do not replace physical acceptance, and no independent reviewer result is implied by this checklist.
