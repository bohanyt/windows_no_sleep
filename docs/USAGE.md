# User guide

[Home](../README.md) · [Safety and recovery](SAFETY.md) · [Documentation](README.md)

## Requirements

Windows x64 with .NET Framework 4.8. Windows 11 is the primary target. Lid, battery, and Modern Standby capabilities depend on the machine and its Windows policy. The native app normally runs as the signed-in user; the supported machine-inactivity operation requests separate administrator approval.

The repository updater also uses Windows `curl.exe` to download assets and Windows PowerShell to verify the EXE hash. Those are updater tools, not the app's runtime. No local compiler is required to use a release.

## Download and launch

Open [the latest stable release](https://github.com/bohanyt/windows_no_sleep/releases/latest). Download these five assets into one folder:

| File | Purpose |
| --- | --- |
| `WindowsNoSleep.exe` | Application. |
| `WindowsNoSleep.exe.config` | Runtime configuration; keep next to the EXE. |
| `README.txt` | Packaged operator instructions and build provenance. |
| `SHA256SUMS.txt` | Expected SHA-256 of the EXE. |
| `BUILD_SHA.txt` | Source commit used for the build. |

The automatically generated **Source code** archives are source snapshots, not prebuilt application packages.

After verifying the download, launch the EXE. Protection starts in the tray. Click its icon to open Settings; closing that window does not exit the application. **Stop** releases protection. Tray **Exit** quits and attempts verified restoration. A duplicate launch shows a short notice instead of creating another protection owner.

Read [the machine-wide inactivity warning](SAFETY.md#machine-wide-inactivity-and-recovery) before enabling that protection, especially on shared or managed computers. A UAC prompt is for that bounded operation, not a reason to run the whole app as administrator.

## Verify a download

Open PowerShell in the folder containing the downloaded assets:

```powershell
Get-FileHash -LiteralPath .\WindowsNoSleep.exe -Algorithm SHA256
Get-Content -LiteralPath .\SHA256SUMS.txt
Get-Content -LiteralPath .\BUILD_SHA.txt
```

Compare the complete 64-character hash with the entry for `WindowsNoSleep.exe`; letter case does not matter. Do not launch the EXE if they differ. The checksum file covers the EXE only. A matching checksum is an integrity check, not a digital signature or security-product approval.

## Update an existing checkout

Exit the app normally first. Double-click `Update Windows No Sleep.cmd` at the repository root, or run this from PowerShell in the repository:

```powershell
& ".\Update Windows No Sleep.cmd"
```

The default is the latest stable non-prerelease release. The updater stages all five assets, verifies the EXE checksum before replacing the installed folder, and launches:

```text
artifacts\local-current\WindowsNoSleep.exe
```

An integrity failure leaves the existing installation untouched. Do not assume every other download, copy, or filesystem failure is automatically rolled back; read the updater's error before trying again. Runtime settings and recovery data are stored separately and are not deleted by the updater.

Development builds are opt-in:

```powershell
& ".\Update Windows No Sleep.cmd" dev
```

`--dev` also works. The updater never silently falls back from stable to development. No repeated clone or new project folder is needed for updates.

## Start with Windows

**Start with Windows (after I sign in)** is off by default. It launches this EXE after the current user signs in, not before login. Enable it only after choosing a permanent app location; the updater's `artifacts\local-current` path is intended to stay stable. Privileged inactivity protection may still request UAC approval.

## Diagnostics and troubleshooting

| Symptom | What to check |
| --- | --- |
| Settings closed, but the app is still running | Expected: closing Settings hides it. Use tray Exit to quit. |
| Updater says the app is running | Exit through the tray, then run the updater again. Do not force-kill it just to update. |
| Display remains on while on battery | Qualifying Modern Standby DC protection requests this intentionally. It should release on AC or when protection stops. |
| Protection is degraded or a setting is unavailable | Read the reported capability or permission warning. Some safe protection can remain active even when one feature is unavailable. |
| Protection pauses on battery | Check Battery Safety, charge level, and whether Windows battery status is readable. |
| Recovery remains pending | Relaunch under the original account and follow the restore warning. Preserve recovery files; do not erase them or guess original values. |
| Security software blocks or quarantines a file | Stop. Record version/hash and the detection details; do not bypass the protection. |

Local data is in `%LOCALAPPDATA%\WindowsNoSleep`, including `settings.json`, pending `recovery.json`, `last-restore.json`, and `events.log`. Diagnostics and `BUILD_SHA.txt` help identify the exact build. For a report, follow [the contribution guide](../CONTRIBUTING.md) and share only relevant, redacted excerpts.
