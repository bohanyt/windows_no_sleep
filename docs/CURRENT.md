# Current project status

**Status: V1 released; post-release maintenance.**

This is the current maintainer entrypoint. Older planning documents and daily handoffs remain historical/design evidence; they do not override this release status. GitHub refs, release metadata, and the latest owner decision remain authoritative when they change.

## Stable release identity

| Field | Published V1 identity |
| --- | --- |
| Release | [Windows No Sleep v1.0.0](https://github.com/bohanyt/windows_no_sleep/releases/tag/v1.0.0) |
| Published | 2026-09-25 |
| Windows file/product version | `1.0.0.0` |
| Release ID | `396730143` |
| Source commit | `c42245aa9edfe3be6186ee84f2cf1b194a1f9188` |
| Source CI run | `36153852605` |
| EXE size | `151040` bytes |
| EXE SHA-256 | `27c1522f622f00acbb2e8ce9dd7224827c34f55c2916ec81cd2f103a8d2d8558` |
| Signing | Unsigned |

The release contains `WindowsNoSleep.exe`, `WindowsNoSleep.exe.config`, `README.txt`, `SHA256SUMS.txt`, and `BUILD_SHA.txt`. The exact main artifact was promoted without rebuilding the executable. PR #4 is merged; V1 is complete. [Final release closure](https://github.com/bohanyt/windows_no_sleep/issues/1#issuecomment-5835162792) records the release disposition.

The source commit above identifies the released binary, not necessarily today's `main` after documentation maintenance. A newer docs-only main commit does not change the installed build SHA or the published assets.

## This maintenance pass

The owner requested immediate public-facing housekeeping. [Recorded scope](https://github.com/bohanyt/windows_no_sleep/issues/1#issuecomment-5835389330): refresh the README, guides, changelog, contribution instructions, and stale status/continuity entrypoints; retain historical evidence and established links.

No application source, native package README, updater, tests, workflow, version metadata, tag, or release asset is changed. No Windows execution or new CI campaign is required for this scope. Keep `v1.0.0` / `1.0.0.0`; no `v1.0.0.1` release is implied. See [the changelog](../CHANGELOG.md).

## Open maintenance and limitations

- The V1 stable-workflow shell-status failure was worked around by exact-artifact promotion. Repairing that workflow is a separate future task; this cleanup does not repair it or authorize another publication.
- [Issue #3](https://github.com/bohanyt/windows_no_sleep/issues/3) remains open as EDR/history tracking. The old PowerShell path remains superseded. Native endpoint acceptance is not universal certification.
- Accepted limitations include option-change UAC behavior, rare PID-reuse delay in broker restoration, and the broker event-ACL finding recorded in the release-review history. Machine-wide auto-lock recovery risk remains documented in [SAFETY.md](SAFETY.md).
- No new physical-Windows task, implementation lane, or release gate is dispatched by this document. Do not revive completed pre-release work from an old handoff.

## Continue maintenance

Read this file, [Control Tower guidance](CONTROL_TOWER.md), and the latest [Issue #1](https://github.com/bohanyt/windows_no_sleep/issues/1) comments. Fresh-check the relevant refs/claims before writing. Read only the design and evidence needed for the new task; keep one implementation owner at a time. Public-facing readers should start with [the app homepage](../README.md), not the historical work queue.
