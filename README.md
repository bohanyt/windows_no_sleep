<p align="center">
  <img src="native/WindowsNoSleep/Assets/WindowsNoSleep.svg" alt="Windows No Sleep icon" width="72" height="72">
</p>

# Windows No Sleep

**Keep your Windows workloads running. Stop when you are done. Restore your settings.**

A portable tray utility for long-running tasks, remote sessions, and supported closed-lid setups. Windows x64 · .NET Framework 4.8 · No installer.

## Download

**[Download the latest stable release](https://github.com/bohanyt/windows_no_sleep/releases/latest)**

Download **`WindowsNoSleep.exe`** and **`WindowsNoSleep.exe.config`** into the same folder. You do not need to clone this repository or download the Source code archives to use the app. The release also includes a checksum file for [verifying your download](docs/USAGE.md#verify-a-download).

Launch the EXE to start protection in the notification area. Click its tray icon for Settings. Closing Settings leaves the app running; use **Stop Protection** or tray **Exit** to release protection and restore temporary settings. **Start with Windows** is optional and off by default.

Already using a repository checkout? Exit the app, then double-click **`Update Windows No Sleep.cmd`** to download and verify the latest stable build.

## Features

- Keep workloads awake, with temporary lid and battery sleep/hibernate settings where supported.
- Battery Safety pauses protection when battery conditions are low, critical, or unreadable.
- A guard for supported normal shutdown/restart requests, plus recovery records for temporary settings.
- Settings, diagnostics, and optional startup after sign-in, all from the tray.

## Important limitations

**Modern Standby on battery:** active battery protection may keep the display logically on and increase battery use. On AC, the display may turn off normally. Keep closed-lid laptops ventilated.

**Automatic locking:** the optional machine-inactivity override affects all signed-in users. After an abnormal exit or power loss, automatic locking can remain changed across reboot until the original account relaunches the app and approves restoration. Read [Safety and recovery](docs/SAFETY.md) before using it on shared or managed computers.

**Security and shutdown:** the app is unsigned. Do not bypass antivirus/EDR detections. Forced shutdowns and every Windows Update deadline cannot be guaranteed to be blocked. Do not delete pending recovery data to clear an error.

## Help and source

[User guide](docs/USAGE.md) · [Safety and recovery](docs/SAFETY.md) · [Changelog](CHANGELOG.md) · [Report a problem](https://github.com/bohanyt/windows_no_sleep/issues)

Application source and tests are in `native/`. See [Building and testing](docs/DEVELOPMENT.md) and [Contributing](CONTRIBUTING.md) to work on the project.
