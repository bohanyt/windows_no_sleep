# Changelog

This file tracks public-facing changes. Build identities and release assets are recorded on the corresponding GitHub release.

## Unreleased

### Documentation

- Reworked the repository homepage around downloading and using the stable app.
- Added dedicated usage, safety/recovery, development, and contribution guides.
- Added a documentation index and an archive index for earlier planning and handoff records.
- Reconciled maintainer entrypoints with the completed V1 release.

This is repository housekeeping only. It does not change the EXE, updater, tests, workflows, release assets, or application version. The stable release remains `v1.0.0`, with Windows file/product version `1.0.0.0`; no `v1.0.0.1` release has been created.

## [1.0.0] — 2026-09-25

First stable native Windows release.

- Portable x64 C# / WinForms application for .NET Framework 4.8.
- System-awake protection, supported temporary lid and DC sleep/hibernate settings, and Battery Safety.
- Modern Standby DC display-request protection, ordinary screensaver suppression, and permission-gated local inactivity protection.
- Normal shutdown/restart guard, tray Settings, diagnostics, and opt-in startup after sign-in.
- Journaled restoration and recovery, including the bounded administrator-approved machine-inactivity broker.
- Stable-by-default updater with explicit development-channel selection and staged EXE checksum verification.

The stable release uses the exact already-built main artifact; the executable was not rebuilt for publication. It remains unsigned. See [safety and limitations](docs/SAFETY.md) and [release provenance](docs/CURRENT.md#stable-release-identity).

[1.0.0]: https://github.com/bohanyt/windows_no_sleep/releases/tag/v1.0.0
