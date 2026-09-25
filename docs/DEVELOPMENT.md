# Building and testing

[Home](../README.md) · [Contributing](../CONTRIBUTING.md) · [Safety](SAFETY.md)

## Source layout

`native/WindowsNoSleep/` contains the C# / WinForms application and project. `native/tests/` contains the Windows SDK ABI assertions. `.github/workflows/` contains the build, test, and release tooling.

`native/README_NATIVE_PILOT.md` is copied into release packages as `README.txt`; its established path is retained for packaging compatibility. The root `Update Windows No Sleep.cmd` downloads prebuilt releases and does not build the source.

## Build on Windows

Use MSBuild with the .NET Framework 4.8 targeting/reference assemblies and x64 support. The ABI check also needs the Windows SDK and C++ build tools. From the repository root in an appropriate developer shell:

```powershell
msbuild .\native\WindowsNoSleep\WindowsNoSleep.csproj /m /t:Rebuild /p:Configuration=Release /p:Platform=x64
if ($LASTEXITCODE -ne 0) { throw 'Native build failed.' }
```

The output is `native\WindowsNoSleep\bin\Release\WindowsNoSleep.exe`. The [build workflow](../.github/workflows/native-pilot.yml) contains the compiler setup, ABI command, and packaging steps.

## Included checks

The following runs the real power-request self-test and fake-provider regressions, not a physical power-policy acceptance campaign:

```powershell
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path .\native\WindowsNoSleep\bin\Release\WindowsNoSleep.exe).Path
New-Item -ItemType Directory -Path .\artifacts -Force | Out-Null
$report = Join-Path (Resolve-Path .\artifacts).Path 'native-v1-tests.txt'
if (Test-Path -LiteralPath $report) { throw 'Move the previous report aside first.' }

$process = Start-Process -FilePath $exe -ArgumentList '--self-test' -PassThru
if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Self-test timed out.' }
$process.Refresh()
if ($process.ExitCode -ne 0) { throw 'Self-test failed.' }

$arguments = '--test-suite "{0}"' -f $report
$process = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru
if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'Regression suite timed out.' }
$process.Refresh()
if ($process.ExitCode -ne 0) { throw 'Regression suite failed.' }
if (-not (Test-Path -LiteralPath $report)) { throw 'Missing regression report.' }
Get-Content -LiteralPath $report
```

These checks do not establish physical lid, battery, standby, UAC, or security-product compatibility. For tests that change Windows settings, obtain permission, record the exact originals, define a restoration plan, and verify restoration. Never run concurrent power-policy mutation tests.

## Releases

Published tags and downloads identify specific builds. Documentation changes do not update the installed app. Do not relabel an old executable as a new version or replace accepted release binaries during documentation cleanup. Keep checksums and build identifiers available for reproducibility and support, without putting internal work logs in the user guide.
