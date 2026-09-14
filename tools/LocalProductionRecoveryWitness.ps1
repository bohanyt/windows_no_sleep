#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$appPath = Join-Path $repoRoot 'WindowsNoSleep.ps1'
$corePath = Join-Path $repoRoot 'src\WindowsNoSleep.Core.psm1'
$powerPolicyPath = Join-Path $repoRoot 'src\WindowsNoSleep.PowerPolicy.psm1'
Import-Module $corePath -Force
Import-Module $powerPolicyPath -Force
Add-Type -AssemblyName System.Windows.Forms

function Assert-Wns {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Test-WnsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-WnsLogPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$TimeoutSeconds = 25
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $Path) {
            $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
            if ($null -ne $text -and $text -match $Pattern) { return $true }
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}

function Save-WnsEvidenceJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )
    [IO.File]::WriteAllText(
        $Path,
        ($Value | ConvertTo-Json -Depth 12),
        (New-Object Text.UTF8Encoding($false))
    )
}

function Get-WnsPolicySnapshot {
    $definitions = Get-WnsPowerPolicyDefinitions
    $scheme = Get-WnsActivePowerSchemeGuid
    return [pscustomobject][ordered]@{
        CapturedUtc = [DateTime]::UtcNow.ToString('o')
        ActiveSchemeGuid = $scheme.ToString()
        Lid = Get-WnsPowerSettingValues -SchemeGuid $scheme -SubGroupGuid $definitions.LidAction.SubGroupGuid -SettingGuid $definitions.LidAction.SettingGuid
        SleepIdle = Get-WnsPowerSettingValues -SchemeGuid $scheme -SubGroupGuid $definitions.SleepIdle.SubGroupGuid -SettingGuid $definitions.SleepIdle.SettingGuid
    }
}

function Get-WnsRecoveryStartupValue {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    try {
        return [string](Get-ItemPropertyValue -Path $key -Name 'WindowsNoSleepRecovery' -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

$expectedScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'
$powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$paths = Get-WnsRuntimePaths
$runOnceBefore = Get-WnsRecoveryStartupValue
$powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus

if (Test-WnsElevated) {
    throw 'Production recovery witness must run non-elevated.'
}
if ($powerStatus.PowerLineStatus -ne [System.Windows.Forms.PowerLineStatus]::Online) {
    throw 'Production recovery witness requires AC connected for the entire test.'
}
if (Test-Path -LiteralPath $paths.BasePath) {
    throw "Refusing to use an existing WindowsNoSleep runtime directory: $($paths.BasePath). Preserve existing user data and STOP."
}
if ($null -ne $runOnceBefore) {
    throw 'A WindowsNoSleepRecovery RunOnce value already exists. Resolve the previous recovery state before this witness.'
}

$before = Get-WnsPolicySnapshot
Assert-Wns ($before.ActiveSchemeGuid -eq $expectedScheme) 'Active scheme does not match the verified Balanced baseline.'
Assert-Wns ([uint32]$before.Lid.AC -eq 0 -and [uint32]$before.Lid.DC -eq 0) 'Lid baseline must remain AC=0/DC=0.'
Assert-Wns ([uint32]$before.SleepIdle.AC -eq 0 -and [uint32]$before.SleepIdle.DC -eq 1200) 'Sleep baseline must remain AC=0/DC=1200.'

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$runDir = Join-Path $repoRoot "artifacts\local-verification\production-recovery-$stamp"
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$resultPath = Join-Path $runDir 'result.json'
$beforePath = Join-Path $runDir 'before.json'
$activePath = Join-Path $runDir 'active.json'
$crashedPath = Join-Path $runDir 'after-crash.json'
$afterPath = Join-Path $runDir 'after-recovery.json'
$logEvidencePath = Join-Path $runDir 'events.log'
$appStdout = Join-Path $runDir 'app.stdout.txt'
$appStderr = Join-Path $runDir 'app.stderr.txt'
$recoveryStdout = Join-Path $runDir 'recovery.stdout.txt'
$recoveryStderr = Join-Path $runDir 'recovery.stderr.txt'
Save-WnsEvidenceJson -Path $beforePath -Value $before

$appProcess = $null
$recoveryProcess = $null
$explicitRecoveryAttempted = $false
$emergencyRecoveryAttempted = $false
$outcome = 'NOT_RUN'
$errorText = $null
$active = $null
$afterCrash = $null
$afterRecovery = $null
$pendingBeforeCrash = $null
$pendingAfterCrash = $null
$hookWhileActive = $null
$hookAfterCrash = $null
$hookAfterRecovery = $null

try {
    Write-Host 'Launching real production tray app...'
    $appProcess = Start-Process `
        -FilePath $powerShellExe `
        -ArgumentList @('-NoProfile', '-STA', '-File', ('"{0}"' -f $appPath)) `
        -RedirectStandardOutput $appStdout `
        -RedirectStandardError $appStderr `
        -PassThru

    if (-not (Wait-WnsLogPattern -Path $paths.LogPath -Pattern 'State -> PROTECTED:' -TimeoutSeconds 25)) {
        $stderr = if (Test-Path -LiteralPath $appStderr) { Get-Content -LiteralPath $appStderr -Raw } else { '' }
        throw "Production app did not reach PROTECTED. $stderr"
    }
    Assert-Wns (-not $appProcess.HasExited) 'Production tray process exited immediately after PROTECTED.'

    $active = Get-WnsPolicySnapshot
    Save-WnsEvidenceJson -Path $activePath -Value $active
    Assert-Wns ($active.ActiveSchemeGuid -eq $expectedScheme) 'Active scheme changed while protection started.'
    Assert-Wns ([uint32]$active.Lid.AC -eq 0 -and [uint32]$active.Lid.DC -eq 0) 'Owner laptop lid values must remain unchanged at 0/0.'
    Assert-Wns ([uint32]$active.SleepIdle.AC -eq 0 -and [uint32]$active.SleepIdle.DC -eq 0) 'Production app did not apply DC SleepIdle Never while protected.'

    $pendingBeforeCrash = Get-WnsRecoveryStatus -Paths $paths
    Assert-Wns ($pendingBeforeCrash.Status -eq 'Pending') 'Production app must persist recovery state while temporary policy is active.'
    $changes = @($pendingBeforeCrash.Snapshot.Changes)
    Assert-Wns ($changes.Count -eq 1) 'Owner laptop production transaction must contain exactly one change.'
    Assert-Wns ($changes[0].Name -eq 'SleepIdle') 'Owner laptop production transaction must be SleepIdle only.'
    Assert-Wns (-not [bool]$changes[0].ApplyAC -and [bool]$changes[0].ApplyDC) 'Production SleepIdle transaction must remain DC-only.'
    Assert-Wns ([uint32]$changes[0].OriginalDC -eq 1200 -and [uint32]$changes[0].TargetDC -eq 0) 'Recovery snapshot must preserve DC 1200 -> 0 exactly.'

    $hookWhileActive = Get-WnsRecoveryStartupValue
    Assert-Wns (-not [string]::IsNullOrWhiteSpace($hookWhileActive)) 'Recovery startup hook must exist before/while temporary policy is active.'

    Write-Host 'PRODUCTION_POLICY_ACTIVE_VERIFIED'
    Write-Host 'Force-killing the tray process to simulate an unclean crash...'
    Stop-Process -Id $appProcess.Id -Force -ErrorAction Stop
    [void]$appProcess.WaitForExit(7000)
    Start-Sleep -Seconds 1

    $afterCrash = Get-WnsPolicySnapshot
    Save-WnsEvidenceJson -Path $crashedPath -Value $afterCrash
    Assert-Wns ([uint32]$afterCrash.SleepIdle.DC -eq 0) 'Temporary DC policy unexpectedly disappeared after process crash; crash-recovery path was not exercised.'
    $pendingAfterCrash = Get-WnsRecoveryStatus -Paths $paths
    Assert-Wns ($pendingAfterCrash.Status -eq 'Pending') 'Recovery snapshot must survive an unclean process kill.'
    $hookAfterCrash = Get-WnsRecoveryStartupValue
    Assert-Wns (-not [string]::IsNullOrWhiteSpace($hookAfterCrash)) 'Recovery startup hook must survive an unclean process kill.'

    Write-Host 'PRODUCTION_CRASH_STATE_VERIFIED'
    Write-Host 'Running the production recovery-only path...'
    $explicitRecoveryAttempted = $true
    $recoveryProcess = Start-Process `
        -FilePath $powerShellExe `
        -ArgumentList @('-NoProfile', '-STA', '-File', ('"{0}"' -f $appPath), '-RecoveryOnly') `
        -RedirectStandardOutput $recoveryStdout `
        -RedirectStandardError $recoveryStderr `
        -PassThru
    Assert-Wns ($recoveryProcess.WaitForExit(15000)) 'Recovery-only process did not finish within 15 seconds.'

    # Do not use child ExitCode as acceptance evidence. Windows PowerShell 5.1
    # can expose a blank ExitCode for redirected Start-Process children on some
    # Windows builds. The authoritative proof is the re-read OS policy and the
    # disappearance of recovery state below.
    $afterRecovery = Get-WnsPolicySnapshot
    Save-WnsEvidenceJson -Path $afterPath -Value $afterRecovery
    Assert-Wns ($afterRecovery.ActiveSchemeGuid -eq $before.ActiveSchemeGuid) 'Recovery changed the active power scheme.'
    Assert-Wns ([uint32]$afterRecovery.Lid.AC -eq [uint32]$before.Lid.AC -and [uint32]$afterRecovery.Lid.DC -eq [uint32]$before.Lid.DC) 'Recovery did not preserve exact lid values.'
    Assert-Wns ([uint32]$afterRecovery.SleepIdle.AC -eq [uint32]$before.SleepIdle.AC -and [uint32]$afterRecovery.SleepIdle.DC -eq [uint32]$before.SleepIdle.DC) 'Recovery did not restore exact SleepIdle originals.'
    Assert-Wns ((Get-WnsRecoveryStatus -Paths $paths).Status -eq 'None') 'Recovery snapshot remained after verified production recovery.'
    $hookAfterRecovery = Get-WnsRecoveryStartupValue
    Assert-Wns ([string]::IsNullOrWhiteSpace($hookAfterRecovery)) 'Recovery startup hook remained after exact restore.'

    if (Test-Path -LiteralPath $paths.LogPath) {
        Copy-Item -LiteralPath $paths.LogPath -Destination $logEvidencePath -Force
    }

    $outcome = 'PRODUCTION_CRASH_RECOVERY_VERIFIED'
    Write-Host 'LOCAL_PRODUCTION_RECOVERY_COMPLETE'
    Write-Host 'Production policy apply, forced-crash persistence, and exact recovery were verified.'
    Write-Host "Evidence: $runDir"
}
catch {
    $errorText = $_.Exception.Message
    $outcome = 'FAILED'
    throw
}
finally {
    if ($null -ne $appProcess) {
        try {
            if (-not $appProcess.HasExited) {
                Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue
                [void]$appProcess.WaitForExit(5000)
            }
        }
        catch {}
        try { $appProcess.Dispose() } catch {}
    }
    if ($null -ne $recoveryProcess) {
        try { $recoveryProcess.Dispose() } catch {}
    }

    # Safety cleanup: if any unexpected failure left a pending transaction,
    # automatically attempt the same production RecoveryOnly path once. Never
    # improvise manual powercfg repair inside this harness.
    try {
        $remaining = Get-WnsRecoveryStatus -Paths $paths
        if ($remaining.Status -eq 'Pending') {
            $emergencyRecoveryAttempted = $true
            $emergency = Start-Process `
                -FilePath $powerShellExe `
                -ArgumentList @('-NoProfile', '-STA', '-File', ('"{0}"' -f $appPath), '-RecoveryOnly') `
                -Wait `
                -PassThru
            $emergency.Dispose()
        }
    }
    catch {}

    try {
        if (Test-Path -LiteralPath $paths.LogPath) {
            Copy-Item -LiteralPath $paths.LogPath -Destination $logEvidencePath -Force
        }
    }
    catch {}

    try { $finalPolicy = Get-WnsPolicySnapshot } catch { $finalPolicy = $null }
    try { $finalRecoveryStatus = (Get-WnsRecoveryStatus -Paths $paths).Status } catch { $finalRecoveryStatus = 'Unreadable' }
    $finalHook = Get-WnsRecoveryStartupValue

    $result = [pscustomobject][ordered]@{
        Outcome = $outcome
        Error = $errorText
        ExplicitRecoveryAttempted = $explicitRecoveryAttempted
        EmergencyRecoveryAttempted = $emergencyRecoveryAttempted
        Before = $before
        WhileProtected = $active
        AfterForcedCrash = $afterCrash
        AfterRecovery = $afterRecovery
        PendingBeforeCrash = if ($null -ne $pendingBeforeCrash) { $pendingBeforeCrash.Status } else { $null }
        PendingAfterCrash = if ($null -ne $pendingAfterCrash) { $pendingAfterCrash.Status } else { $null }
        RecoveryHookWhileActive = $hookWhileActive
        RecoveryHookAfterCrash = $hookAfterCrash
        RecoveryHookAfterRecovery = $hookAfterRecovery
        FinalPolicy = $finalPolicy
        FinalRecoveryStatus = $finalRecoveryStatus
        FinalRecoveryHook = $finalHook
    }
    try { Save-WnsEvidenceJson -Path $resultPath -Value $result } catch {}

    if ($outcome -eq 'PRODUCTION_CRASH_RECOVERY_VERIFIED' -and $finalRecoveryStatus -eq 'None' -and [string]::IsNullOrWhiteSpace($finalHook)) {
        try { Remove-Item -LiteralPath $paths.BasePath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
