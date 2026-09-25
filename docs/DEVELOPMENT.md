# Development

[Documentation](README.md) · [Contributing](../CONTRIBUTING.md) · [Current status](CURRENT.md)

## Repository layout

| Path | Purpose |
| --- | --- |
| `native/WindowsNoSleep/` | Current C# / WinForms application and project. |
| `native/tests/` | Windows SDK ABI assertions. |
| `native/README_NATIVE_PILOT.md` | Operator text copied into release packages; established filename retained. |
| `.github/workflows/` | Build/test and exact-artifact release tooling. |
| `Update Windows No Sleep.cmd` | Stable-by-default local updater; `dev` is explicit. |
| `docs/` | User guides, design references, and maintainer navigation. |
| `legacy/` | Historical third-party material, not the current runtime. |

## Build on Windows

Use MSBuild with the .NET Framework 4.8 targeting/reference assemblies and x64 support. The ABI check additionally needs the Windows SDK and C++ build tools. Run from the repository root in an appropriate developer shell:

```powershell
msbuild .\native\WindowsNoSleep\WindowsNoSleep.csproj /m /t:Rebuild /p:Configuration=Release /p:Platform=x64
if ($LASTEXITCODE -ne 0) { throw 'Native build failed.' }
```

The build output is `native\WindowsNoSleep\bin\Release\WindowsNoSleep.exe`. The checked-in workflow is the detailed reference for its compiler setup, ABI command, packaging, and proof steps; this guide does not replace it.

## Run the built-in checks

The following mirrors the checked-in workflow's non-policy-mutating self-test and fake-provider regression suite. It does not prove physical lid, battery, standby, or security-product behavior.

```powershell
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path .\native\WindowsNoSleep\bin\Release\WindowsNoSleep.exe).Path
New-Item -ItemType Directory -Path .\artifacts -Force | Out-Null

$process = Start-Process -FilePath $exe -ArgumentList '--self-test' -PassThru
if (-not $process.WaitForExit(30000)) {
    $process.Kill()
    throw 'Power-request self-test timed out.'
}
$process.Refresh()
if ($process.ExitCode -ne 0) { throw "Self-test failed: $($process.ExitCode)" }

$report = Join-Path (Resolve-Path .\artifacts).Path 'native-v1-tests.txt'
if (Test-Path -LiteralPath $report) {
    throw 'Move the previous test report aside so this run produces fresh evidence.'
}
$arguments = '--test-suite "{0}"' -f $report
$process = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru
if (-not $process.WaitForExit(120000)) {
    $process.Kill()
    throw 'Regression suite timed out.'
}
$process.Refresh()
if ($process.ExitCode -ne 0) { throw "Regression suite failed: $($process.ExitCode)" }
if (-not (Test-Path -LiteralPath $report)) { throw 'Missing regression report.' }
Get-Content -LiteralPath $report
```

These commands are documented from the release-source workflow, not newly executed as part of the post-release documentation cleanup.

## Tests that require explicit physical execution

Permission/elevation, real power-setting mutation/restoration, Modern Standby, lid closure, AC/DC transitions, battery safety, tray interaction, and endpoint-security acceptance need the intended Windows environment. Do not silently substitute a compile or mock test for this evidence.

Use the [test plan](TEST_PLAN.md), [native acceptance record](NATIVE_V1_ACCEPTANCE.md), and the current bounded task. Snapshot original values, record the exact source/EXE identity, and verify restoration. Never run concurrent power-policy mutation tests. Historical dispatches are not fresh permission to execute them.

## Release and version boundaries

The stable release is `v1.0.0`; the Windows file/product version is `1.0.0.0`. Post-release README or navigation changes do not change that binary identity. Do not create a tag with a newer version and attach the old executable as though it were a new build.

The release model is promotion of an accepted, already-built main artifact, not a rebuild at tag time. Keep source SHA, build run, version, checksum, and published asset identity tied together. The V1 publication used a manually completed exact-artifact promotion after a workflow shell-status failure; a future workflow repair is separate maintenance, not something this documentation pass fixes.

Docs-only changes should avoid unnecessary build/publication runs. Runtime, packaging, workflow, updater, or version changes still need their appropriate proof; do not use a docs-only CI skip to hide those changes. See [current status](CURRENT.md) before scheduling CI or release work.
