# Windows No Sleep — native pilot

This branch is the minimal compiled pilot created after Issue #3 exposed endpoint-security compatibility problems with the PowerShell-first runtime.

## What this pilot does

- builds `WindowsNoSleep.exe` as a conventional C# WinForms application targeting .NET Framework 4.8;
- starts `PowerRequestSystemRequired` immediately;
- exposes a tray icon and small Settings/status window;
- supports Start/Stop Protection and Exit;
- releases its owned power-request handle on Stop/Exit;
- runs non-elevated.

## What this pilot deliberately does NOT do

- no PowerShell/CMD/script-host child process;
- no lid-action mutation;
- no AC/DC sleep-timeout mutation;
- no registry startup entry;
- no RunOnce recovery;
- no recovery journal yet;
- no shutdown/restart blocker yet;
- no battery-safety controller yet;
- no installer;
- no code signing yet;
- no AV/EDR exclusion or bypass.

The purpose of this pilot is to validate the boring compiled packaging/runtime direction on a protected endpoint **before** porting the rest of V1.

## Build

```powershell
msbuild .\native\WindowsNoSleep\WindowsNoSleep.csproj /p:Configuration=Release /p:Platform=x64
```

Expected output:

```text
native\WindowsNoSleep\bin\Release\WindowsNoSleep.exe
```

## CI self-test

The CI self-test launches the exact compiled EXE with `--self-test`. It acquires and releases only a `PowerRequestSystemRequired` lease. It does not write power policy, startup registry state, or recovery persistence.

Physical protected-endpoint execution requires a separate Control Tower dispatch after hosted build/self-test evidence is green.
