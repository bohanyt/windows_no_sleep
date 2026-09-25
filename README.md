<p align="center">
  <img src="native/WindowsNoSleep/Assets/WindowsNoSleep.svg" alt="Windows No Sleep icon" width="72" height="72">
</p>

# Windows No Sleep

**Keep your Windows workloads running, with temporary settings that restore when you stop.**

A portable tray utility for long-running tasks, remote sessions, and supported closed-lid setups. Built with C# and WinForms for Windows x64 and .NET Framework 4.8.

**[Download the latest stable release](https://github.com/bohanyt/windows_no_sleep/releases/latest)** · [User guide](docs/USAGE.md) · [Safety and recovery](docs/SAFETY.md) · [Changelog](CHANGELOG.md)

## Get started

1. Open the **latest stable release** above. Download `WindowsNoSleep.exe` and `WindowsNoSleep.exe.config` into the same folder. Also keep `README.txt`, `SHA256SUMS.txt`, and `BUILD_SHA.txt` for instructions and build verification.
2. Follow the [checksum instructions](docs/USAGE.md#verify-a-download), then launch `WindowsNoSleep.exe`. Protection starts in the notification area; some optional protection may request administrator approval.
3. Click the tray icon to open Settings. Closing Settings leaves the app running. Use **Stop** to release protection, or right-click the tray icon and choose **Exit** to quit and restore temporary settings.

No installer or local build tools are required to use the release. **Start with Windows** is optional and off by default.

Already using a repository checkout? Exit the app, then double-click **`Update Windows No Sleep.cmd`**. It downloads the latest stable build, checks the EXE checksum, and launches it from `artifacts\local-current`. Development builds require an explicit `dev` argument; the updater does not silently switch channels.

## What it does

| Capability | What to expect |
| --- | --- |
| Keep workloads awake | Requests that Windows keep the system running. Display-off is normally allowed, with a Modern Standby battery exception below. |
| Lid and battery protection | Temporarily adjusts supported lid and battery sleep/hibernate settings where Windows permits it. |
| Battery Safety | Releases protection at low, critical, or unreadable battery conditions on DC rather than keeping the machine awake at any cost. |
| Shutdown/restart guard | Shows a block reason for supported normal shutdown/restart requests; it cannot guarantee prevention of forced shutdowns or every update deadline. |
| Restore and recover | Records original settings before changing them, verifies restoration, and preserves unresolved recovery data. |

## Know before you use it

**On Modern Standby laptops, active battery protection can keep the display logically on.** This avoids the display-idle standby path, but can increase battery use. On AC, the display may turn off normally. Keep closed-lid laptops properly ventilated.

**The optional machine-inactivity override affects automatic locking for all signed-in users.** After an abnormal exit or power loss, that setting can remain changed across reboot until the original account relaunches the app and approves restoration. Read [the recovery warning](docs/SAFETY.md#machine-wide-inactivity-and-recovery) before enabling it, particularly on shared or managed computers.

The release is **unsigned**. Compatibility on one tested endpoint does not certify every antivirus or EDR configuration. Do not disable security software or bypass a detection to run it. Do not delete pending recovery data to clear an error.

## Documentation and source

- **Using the app:** [setup, updating, diagnostics, and troubleshooting](docs/USAGE.md).
- **Understanding the safeguards:** [battery, permissions, shutdown limits, and recovery](docs/SAFETY.md).
- **Working on the project:** [build and test guide](docs/DEVELOPMENT.md), [contributing](CONTRIBUTING.md), and the [documentation index](docs/README.md).

Application source is in `native/`; `legacy/` is historical reference material, not the current app. Maintainer status and development history are kept out of the user guide: see [current project status](docs/CURRENT.md) and [the archive index](docs/archive/README.md).
