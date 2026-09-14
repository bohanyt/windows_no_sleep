#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateRange(60, 600)]
    [int]$WitnessSeconds = 120,

    [ValidateRange(2, 30)]
    [int]$MaximumHealthyGapSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$appPath = Join-Path $repoRoot 'WindowsNoSleep.ps1'
$powerPolicyPath = Join-Path $repoRoot 'src\WindowsNoSleep.PowerPolicy.psm1'
Import-Module $powerPolicyPath -Force
Add-Type -AssemblyName System.Windows.Forms

function Test-WnsCurrentProcessElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-WnsLogPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$TimeoutSeconds = 20
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $Path) {
            $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
            if ($null -ne $text -and $text -match $Pattern) {
                return $true
            }
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    return $false
}

function Save-WnsJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

if (Test-WnsCurrentProcessElevated) {
    throw 'Lid witness must run from the normal non-elevated user session.'
}

$powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
if ($powerStatus.PowerLineStatus -ne [System.Windows.Forms.PowerLineStatus]::Online) {
    throw 'Lid witness requires AC power. Connect the charger and keep it connected for the entire witness.'
}

$definitions = Get-WnsPowerPolicyDefinitions
$scheme = Get-WnsActivePowerSchemeGuid
$lid = Get-WnsPowerSettingValues -SchemeGuid $scheme -SubGroupGuid $definitions.LidAction.SubGroupGuid -SettingGuid $definitions.LidAction.SettingGuid
$sleep = Get-WnsPowerSettingValues -SchemeGuid $scheme -SubGroupGuid $definitions.SleepIdle.SubGroupGuid -SettingGuid $definitions.SleepIdle.SettingGuid

$expectedScheme = [Guid]'381b4222-f694-41f0-9685-ff5bb260df2e'
if ($scheme -ne $expectedScheme) {
    throw "Active power scheme changed from the verified Dispatch 002 baseline. Expected $expectedScheme, got $scheme. No lid test authorized."
}
if ([uint32]$lid.AC -ne 0 -or [uint32]$lid.DC -ne 0) {
    throw "Lid policy no longer matches verified baseline AC=0/DC=0. Got AC=$($lid.AC)/DC=$($lid.DC). No lid test authorized."
}
if ([uint32]$sleep.AC -ne 0 -or [uint32]$sleep.DC -ne 1200) {
    throw "Sleep idle no longer matches verified baseline AC=0/DC=1200. Got AC=$($sleep.AC)/DC=$($sleep.DC). No lid test authorized."
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$runDir = Join-Path $repoRoot "artifacts\local-verification\lid-$stamp"
$runtimeRoot = Join-Path $runDir 'localappdata'
$runtimeDir = Join-Path $runtimeRoot 'WindowsNoSleep'
$logPath = Join-Path $runtimeDir 'events.log'
$heartbeatPath = Join-Path $runDir 'heartbeat.txt'
$resultPath = Join-Path $runDir 'result.json'
$stdoutPath = Join-Path $runDir 'app.stdout.txt'
$stderrPath = Join-Path $runDir 'app.stderr.txt'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null

$powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$appProcess = $null
$startedUtc = [DateTime]::UtcNow
$heartbeatTimes = New-Object System.Collections.Generic.List[DateTime]
$outcome = 'NOT_RUN'
$errorText = $null
$maxGapSeconds = $null

try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $powerShellExe
    $psi.Arguments = '-NoProfile -STA -File "{0}"' -f $appPath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['LOCALAPPDATA'] = $runtimeRoot

    $appProcess = New-Object Diagnostics.Process
    $appProcess.StartInfo = $psi
    [void]$appProcess.Start()

    if (-not (Wait-WnsLogPattern -Path $logPath -Pattern 'State -> PROTECTED:' -TimeoutSeconds 20)) {
        $stderr = if ($appProcess.HasExited) { $appProcess.StandardError.ReadToEnd() } else { '' }
        throw "Tray app did not reach PROTECTED before lid witness. $stderr"
    }
    if ($appProcess.HasExited) {
        throw 'Tray app exited unexpectedly before lid witness.'
    }

    Write-Host 'LOCAL_LID_WITNESS_READY'
    Write-Host "Evidence: $runDir"
    Write-Host "App PID: $($appProcess.Id)"
    Write-Host "Witness duration: $WitnessSeconds seconds"
    Write-Host 'Close the physical laptop lid NOW. Keep it closed for about 90 seconds using an external timer, then reopen it. Do not unplug AC.'

    $deadline = [DateTime]::UtcNow.AddSeconds($WitnessSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $now = [DateTime]::UtcNow
        $heartbeatTimes.Add($now)
        Add-Content -LiteralPath $heartbeatPath -Value $now.ToString('o') -Encoding UTF8
        Start-Sleep -Seconds 1
    }

    if ($heartbeatTimes.Count -lt 2) {
        throw 'Heartbeat witness did not collect enough samples.'
    }

    $largest = 0.0
    for ($i = 1; $i -lt $heartbeatTimes.Count; $i++) {
        $gap = ($heartbeatTimes[$i] - $heartbeatTimes[$i - 1]).TotalSeconds
        if ($gap -gt $largest) {
            $largest = $gap
        }
    }
    $maxGapSeconds = [Math]::Round($largest, 3)

    if ($appProcess.HasExited) {
        throw 'Tray app exited during the lid witness.'
    }

    if ($largest -gt $MaximumHealthyGapSeconds) {
        $outcome = 'EXECUTION_GAP_DETECTED'
        throw "Heartbeat gap $maxGapSeconds seconds exceeds allowed $MaximumHealthyGapSeconds seconds. The workload was not continuously scheduled while the lid was closed."
    }

    $outcome = 'LID_CLOSED_WORKLOAD_CONTINUED'
    Write-Host 'LOCAL_LID_WITNESS_COMPLETE'
    Write-Host "Maximum heartbeat gap: $maxGapSeconds seconds"
    Write-Host 'The independent workload continued while the physical lid/display was closed.'
}
catch {
    $errorText = $_.Exception.Message
    if ($outcome -eq 'NOT_RUN') {
        $outcome = 'FAILED'
    }
    throw
}
finally {
    $endedUtc = [DateTime]::UtcNow

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

    $finalScheme = $null
    $finalLid = $null
    $finalSleep = $null
    try {
        $finalScheme = Get-WnsActivePowerSchemeGuid
        $finalLid = Get-WnsPowerSettingValues -SchemeGuid $finalScheme -SubGroupGuid $definitions.LidAction.SubGroupGuid -SettingGuid $definitions.LidAction.SettingGuid
        $finalSleep = Get-WnsPowerSettingValues -SchemeGuid $finalScheme -SubGroupGuid $definitions.SleepIdle.SubGroupGuid -SettingGuid $definitions.SleepIdle.SettingGuid
    }
    catch {}

    $result = [pscustomobject][ordered]@{
        StartedUtc = $startedUtc.ToString('o')
        EndedUtc = $endedUtc.ToString('o')
        WitnessSeconds = $WitnessSeconds
        MaximumHealthyGapSeconds = $MaximumHealthyGapSeconds
        HeartbeatSamples = $heartbeatTimes.Count
        MaximumObservedGapSeconds = $maxGapSeconds
        Outcome = $outcome
        Error = $errorText
        Before = [pscustomobject][ordered]@{
            ActiveSchemeGuid = $scheme.ToString()
            Lid = $lid
            SleepIdle = $sleep
        }
        After = [pscustomobject][ordered]@{
            ActiveSchemeGuid = if ($null -ne $finalScheme) { $finalScheme.ToString() } else { $null }
            Lid = $finalLid
            SleepIdle = $finalSleep
        }
    }
    Save-WnsJson -Path $resultPath -Value $result
}
