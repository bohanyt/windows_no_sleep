# Windows No Sleep

Portable tray utility for Windows x64 with .NET Framework 4.8. Keeps workloads running with temporary settings that are restored when protection stops.

User guide: https://github.com/bohanyt/windows_no_sleep/blob/main/docs/USAGE.md
Safety and recovery: https://github.com/bohanyt/windows_no_sleep/blob/main/docs/SAFETY.md

## Run

Keep WindowsNoSleep.exe and WindowsNoSleep.exe.config together. Verify the EXE against SHA256SUMS.txt, then launch it. The text files provide instructions, checksum verification, and build identification; they are not additional programs to install.

Protection starts in the tray. Click the icon for Settings. Closing Settings leaves the app running. Use Stop Protection to release protection, or tray Exit to quit and restore temporary settings. A duplicate launch shows a short notice rather than starting another protection owner.

Start with Windows is optional and OFF by default. Choose a permanent executable location before enabling it. Startup happens after the current user signs in; privileged inactivity protection may still request administrator approval.

## Update

Exit the app normally first. In a repository checkout, run Update Windows No Sleep.cmd with no argument for the latest stable release. The updater checks the EXE checksum and uses artifacts\local-current. Development builds require an explicit dev argument; there is no silent fallback.

For manual installations, download the files from the latest stable release and verify the EXE checksum before launching the replacement:
https://github.com/bohanyt/windows_no_sleep/releases/latest

## Important limitations

- Modern Standby battery protection can keep the display logically on, increasing battery use. On AC, the display may turn off normally. Keep closed-lid laptops ventilated.
- Battery Safety releases protection at low, critical, or unreadable DC battery conditions. Its base threshold is 15%, raised when a readable Windows critical threshold plus five requires it. Five-point hysteresis prevents rapid pause/resume cycling.
- Supported temporary power changes are limited to lid action AC/DC and sleep/hibernate timeouts on DC. Windows Update services, global hibernation, power-button actions, critical-battery actions, and thermal protection are not disabled.
- The normal shutdown/restart guard cannot guarantee protection against forced shutdown, logoff, power loss, or every Windows Update deadline. Save work normally.

## Machine-wide automatic-lock warning

The optional machine-inactivity override changes InactivityTimeoutSecs for ALL signed-in users/sessions. Use it only where you are authorized to change automatic-lock behavior. After explicit UAC approval, an elevated broker is intended to restore the exact original value on Stop/Exit or when the main app disappears.

Power loss, security software terminating the broker, an unclean session end, or an elevated main app without a surviving broker can leave automatic locking disabled across reboot for all users. The recovery record belongs to the original account in %LOCALAPPDATA%; another account does not automatically repair it. The original account must relaunch Windows No Sleep and approve the administrator restore helper. Startup is OFF by default, so this may wait until that account launches the app.

Rare fast process-ID reuse can delay broker restoration until that unrelated process exits or the original account relaunches and restores. Changing protection options restarts protection and may request UAC again, including after a previous denial.

## Recovery and security

Settings and diagnostics live under %LOCALAPPDATA%\WindowsNoSleep. Do not delete pending recovery records to clear an error. The app refuses new policy writes while restoration is unresolved. After an abnormal exit, settings not restored by a surviving broker rely on next-launch recovery. Crash/hang recovery is best effort, not guaranteed. Follow the reported recovery action; never guess original values.

The release is unsigned. A matching checksum verifies EXE integrity, not a digital signature or universal antivirus/EDR approval. Stop on a security detection; do not disable security software, add exclusions, or force quarantined files to run.

Report problems with the app version, relevant settings, and redacted diagnostic excerpts:
https://github.com/bohanyt/windows_no_sleep/issues
