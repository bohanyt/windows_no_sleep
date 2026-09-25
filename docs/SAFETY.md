# Safety, permissions, and recovery

[Home](../README.md) · [User guide](USAGE.md) · [Documentation](README.md)

Windows No Sleep prioritizes battery safety and restoration over staying awake. It cannot make every device, policy, or shutdown path behave the same way.

## Battery and display behavior

The normal system-awake request allows the display to turn off. On qualifying Modern Standby hardware while protected on battery/DC, a separate transient display request keeps the display logically on to avoid display-idle standby entry. This can increase battery use. The request releases on AC, Stop, Suspend, cleanup, or Battery Safety. Closing the lid may still darken the physical panel.

Battery Safety has a 15% base threshold, raised when a readable Windows critical-battery threshold plus five percentage points requires it. Low, critical, or unreadable DC battery conditions release blockers and restore temporary settings. A five-point hysteresis helps avoid rapid pause/resume cycling. AC can permit resumption, but does not override unresolved recovery errors.

Keep ventilation clear during closed-lid operation. Do not use the utility to defeat thermal protection or critical-battery actions.

## Which settings may change

Power-policy writes are limited to supported **LidAction AC/DC**, **SleepIdle DC**, and **HibernateIdle DC** values. The app records original values before a write and verifies restoration. It does not change AC sleep/display timeouts, power-button actions, critical-battery actions, the active power scheme, Windows Update services, or the global hibernation feature.

Ordinary screensaver suppression and the separately permission-gated machine-inactivity override are additional protections. Capabilities blocked by permissions or policy are reported, not bypassed. Changing a protection option restarts protection; when machine-inactivity protection is requested, that can produce another UAC prompt, including after a previous denial.

## Machine-wide inactivity and recovery

**This option temporarily changes the machine-wide `InactivityTimeoutSecs` policy and affects every signed-in user/session.** Only use it where you are authorized to change automatic-lock behavior. Do not assume that keeping work running requires disabling automatic locking.

After explicit UAC approval, a bounded elevated broker holds responsibility for restoring the exact original inactivity value. It is intended to restore the value and exit when the main app disappears. Normal Stop/Exit uses the already-approved broker for restoration.

**Restoration is not guaranteed after every abnormal exit.** Power loss, security software terminating the broker, an unclean session end, or an elevated main app without a surviving broker can leave machine-wide inactivity auto-lock disabled across reboot for all users. Nothing can execute a restore while power is absent.

The recovery record is bound to the original account in `%LOCALAPPDATA%`. Another account does not automatically repair it. The original account must relaunch Windows No Sleep and approve the one-shot administrator restore helper to restore the recorded original. Automatic startup is off by default, so that recovery may not happen until the account launches the app.

In the rare case of fast process-ID reuse after the main app exits, broker restoration can be delayed until the unrelated process with that ID exits or the original account relaunches and restores. This remains a documented limitation, not a guarantee of immediate crash recovery.

## Unresolved restoration

Use Stop or tray Exit for normal cleanup. After hard termination, power loss, or security termination, settings not restored by the surviving broker rely on the next-launch recovery journal. Application Restart and Recovery registration is best effort, not a substitute for checking restoration.

Do not delete pending, corrupt, foreign, or conflicting recovery records to silence a warning. The application refuses new policy writes while restoration is unresolved. Preserve the records and relevant log excerpts, relaunch under the original account, and follow the reported recovery action. Do not invent original values or overwrite another actor's changes.

The updater keeps runtime data separate under `%LOCALAPPDATA%\WindowsNoSleep`; updating the executable does not itself prove that recovery is complete.

## Shutdown and restart limits

The app uses a supported GUI block reason for normal shutdown/restart requests. Forced or critical shutdown, logoff, power loss, and every Windows Update deadline are not guaranteed to be blocked. Windows Update services remain enabled. Save work and use normal maintenance procedures rather than treating the guard as a backup system.

## Signing and endpoint security

The stable executable is unsigned. Acceptance on a particular Windows/SentinelOne endpoint is evidence about that tested endpoint and package, not universal antivirus/EDR certification.

Stop on a security detection. Do not disable security software, add exclusions, restore quarantined files for a forced rerun, or revive the superseded PowerShell launcher. Explicit UAC for the supported inactivity operation is distinct from a security-bypass workaround. See [the historical EDR issue](https://github.com/bohanyt/windows_no_sleep/issues/3) and [reporting guidance](../CONTRIBUTING.md).
