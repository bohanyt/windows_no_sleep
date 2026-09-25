# User guide

[Home](../README.md) · [Safety and recovery](SAFETY.md)

## Requirements

Windows x64 with .NET Framework 4.8. Windows 11 is the primary target. Lid, battery, and Modern Standby capabilities depend on the machine and its Windows policy. The app normally runs as the signed-in user; the supported machine-inactivity operation requests separate administrator approval.

No compiler, repository checkout, or developer tools are needed to use a release. The optional repository updater uses Windows `curl.exe` for downloads and Windows PowerShell for checksum verification.

## Download and launch

Open [the latest stable release](https://github.com/bohanyt/windows_no_sleep/releases/latest). Put **`WindowsNoSleep.exe`** and **`WindowsNoSleep.exe.config`** in the same folder. These are the application and its runtime configuration.

The other files have supporting roles: `SHA256SUMS.txt` lets you verify the EXE download; `README.txt` contains instructions; `BUILD_SHA.txt` identifies the build for diagnostics. They are not additional programs to install. The app can start without the text files, but keeping them is useful for verification and troubleshooting. The updater still downloads all five automatically.

The **Source code** archives are for developers, not prebuilt application packages.

[Verify the download](#verify-a-download), then launch the EXE. Protection starts in the tray. Click its icon for Settings. Closing Settings leaves the app running. **Stop Protection** releases protection; tray **Exit** quits and attempts verified restoration. A duplicate launch shows a short notice instead of creating another protection owner.

Read [the machine-wide inactivity warning](SAFETY.md#machine-wide-inactivity-and-recovery) before enabling that option, especially on shared or managed computers. Its UAC prompt is not a reason to run the whole app as administrator.

## Verify a download

Download `SHA256SUMS.txt` from the same release. Open PowerShell in the app folder:

```powershell
Get-FileHash -LiteralPath .\WindowsNoSleep.exe -Algorithm SHA256
Get-Content -LiteralPath .\SHA256SUMS.txt
```

Compare the complete 64-character hash with the entry for `WindowsNoSleep.exe`; letter case does not matter. Do not launch the EXE if they differ. This file covers the EXE only. A matching checksum is an integrity check, not a digital signature or antivirus approval.

## Update

Exit the app normally before replacing its files. With a repository checkout, double-click `Update Windows No Sleep.cmd`, or run:

```powershell
& ".\Update Windows No Sleep.cmd"
```

The updater downloads the latest stable release, verifies the EXE checksum, and launches `artifacts\local-current\WindowsNoSleep.exe`. An integrity failure leaves the previous installation untouched. Other copy or filesystem failures are not guaranteed to roll back automatically; read the error before retrying. Settings and recovery data are stored separately and are not deleted by the updater.

For a manually downloaded app, get the files from the latest stable release and repeat the checksum check before launching the replacement.

Development builds are opt-in with `Update Windows No Sleep.cmd dev` or `--dev`. The updater never silently switches from stable to development.

## Start with Windows

**Start with Windows (after I sign in)** is off by default. It starts this EXE after the current user signs in, not before login. Choose a permanent app location before enabling it. The updater's `artifacts\local-current` path stays stable. Privileged inactivity protection may still request UAC approval.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Settings closed, but the app is still running | Expected. Use tray Exit to quit. |
| Updater says the app is running | Exit through the tray, then retry. Do not force-kill it just to update. |
| Display stays on while on battery | Qualifying Modern Standby battery protection requests this intentionally. It releases on AC or when protection stops. |
| Protection is degraded | Read the capability or permission warning. Other safe protection may remain active. |
| Protection pauses on battery | Check Battery Safety, charge level, and whether Windows can read the battery status. |
| Recovery stays pending | Relaunch under the original account and follow the restore warning. Do not erase recovery files or guess original settings. |
| Security software blocks a file | Stop and record the detection details. Do not bypass protection. |

Local data is in `%LOCALAPPDATA%\WindowsNoSleep`, including `settings.json`, pending `recovery.json`, `last-restore.json`, and `events.log`. Do not delete these records merely to clear a warning. For a report, use [GitHub Issues](https://github.com/bohanyt/windows_no_sleep/issues) and share only relevant, redacted excerpts.
