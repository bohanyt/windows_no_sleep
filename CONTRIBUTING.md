# Contributing

Thanks for helping improve Windows No Sleep. Start with the [user guide](docs/USAGE.md) and [safety information](docs/SAFETY.md).

## Report a problem

Open a [GitHub issue](https://github.com/bohanyt/windows_no_sleep/issues) with the app version, Windows version, what happened, what you expected, and steps to reproduce it. For power-related problems, include AC versus battery, lid position, relevant settings, and the status shown in Diagnostics. The build identifier can help distinguish otherwise similar builds.

Share only relevant log excerpts. Remove usernames, machine names, private paths, and unrelated information. Never post credentials or delete pending recovery records to prepare a report.

For a security-software detection, stop using the affected package and report its version, checksum, and detection details. Do not disable protection, add exclusions, or force a quarantined file to run.

## Propose a change

Keep pull requests focused. Discuss new features and power/recovery changes before implementation. Describe the problem, scope, tests actually run, and remaining limitations. See [Building and testing](docs/DEVELOPMENT.md).

Preserve exact-original restoration and unresolved recovery records. Do not disable Windows Update, global hibernation, antivirus/EDR, critical-battery actions, or thermal protection. Never run power-setting mutation tests on someone else's machine without permission and a restoration plan.

A compile or simulated test is not proof of physical lid, battery, standby, or endpoint-security behavior. Do not relabel an old executable as a new version. Release decisions remain with the maintainer.

## Licensing

No project-wide license is currently declared. This cleanup does not grant a new license. Contact the maintainer about reuse or licensing before incorporating third-party code or assets.
