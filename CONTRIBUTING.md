# Contributing to Windows No Sleep

Thanks for helping improve the project. Start with the [user guide](docs/USAGE.md), [safety contract](docs/SAFETY.md), and [current project status](docs/CURRENT.md).

## Report a problem

Use [GitHub Issues](https://github.com/bohanyt/windows_no_sleep/issues). Include the app version and build SHA, Windows version, what you expected, what happened, and a short reproduction. For power-related problems, also describe AC versus battery, lid position, relevant settings, and the status shown in Settings or Diagnostics.

Share only the relevant log excerpt. Remove usernames, machine names, private paths, and unrelated information. Do not post credentials or complete private diagnostic archives. Do not delete local recovery records while preparing a report.

For a security-software detection, stop using the affected package and report the exact release, EXE hash, and detection details. Do not disable protection, restore quarantined files for a forced rerun, or add exclusions as a workaround.

## Propose a change

Keep changes focused. Discuss new features or power/recovery behavior before implementing them, so they do not conflict with another active task. Separate documentation cleanup from runtime changes. Describe the problem, scope, tests actually run, and any limitations in the pull request.

A Windows build is not proof of physical lid, battery, Modern Standby, recovery, or endpoint-security behavior. Use [the development guide](docs/DEVELOPMENT.md) and record evidence accurately. Never run power-setting mutation tests on someone else's machine without explicit permission and a restoration plan.

## Non-negotiable safeguards

Do not disable Windows Update services, global hibernation, antivirus/EDR, critical-battery actions, or thermal protection. Do not add input simulation or permanent policy changes to work around a failed capability. Preserve exact-original restoration and unresolved recovery evidence.

Do not repackage an existing executable under a new version, overwrite a published release, or imply that unsigned builds are universally security-certified. Release decisions remain with the owner.

## Licensing

No project-wide root `LICENSE` is currently declared. `legacy/LICENSE` belongs to the historical third-party material. This documentation cleanup does not select a new license or expand that legacy license to the native app. Confirm licensing with the owner before incorporating third-party code or assets.
