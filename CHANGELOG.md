# Changelog

## Unreleased

- Simplified the public documentation and removed obsolete reference files from the current repository tree. No application behavior or published download changed.

## 1.0.0 — 2026-09-25

First stable native Windows release.

- Portable tray app with Settings, diagnostics, and optional startup after sign-in.
- System-awake protection, supported temporary lid and battery sleep/hibernate settings, and Battery Safety.
- Modern Standby battery protection, screensaver protection, and a permission-gated machine-inactivity option.
- Normal shutdown/restart guard, verified restoration of owned settings, and recovery records for interrupted sessions.
- Stable-by-default updater with EXE checksum verification.

The release is unsigned. See [Safety and recovery](docs/SAFETY.md) for battery/display behavior, machine-wide automatic-lock recovery risks, and shutdown limits.

[Download v1.0.0](https://github.com/bohanyt/windows_no_sleep/releases/tag/v1.0.0)
