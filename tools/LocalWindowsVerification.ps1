#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Probe', 'ApplyRestoreSmoke')]
    [string]$Mode = 'Probe',

    [switch]$AcknowledgeTemporaryPowerPolicyChange
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$corePath = Join-Path $repoRoot 'src\WindowsNoSleep.Core.psm1'
$powerPolicyPath = Join-Path $repoRoot 'src\WindowsNoSleep.PowerPolicy.psm1'
$transactionPath = Join-Path $repoRoot 'src\WindowsNoSleep.PolicyTransaction.psm1'

Import-Module $transactionPath -Force
Import-Module $corePath -Force
Import-Module $powerPolicyPath -Force
Add-Type -AssemblyName System.Windows.Forms

function Test-WnsCurrentProcessElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-WnsReadOnlyCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Arguments
    )

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()

    return [pscustomobject][ordered]@{
        ExitCode = $exitCode
        StdOut = $stdout.Trim()
        StdErr = $stderr.Trim()
    }
}

function Get-WnsLocalPowerSnapshot {
    $definitions = Get-WnsPowerPolicyDefinitions
    $scheme = Get-WnsActivePowerSchemeGuid

    $lid = $null
    $lidError = $null
    try {
        $lid = Get-WnsPowerSettingValues -SchemeGuid $scheme -SubGroupGuid $definitions.LidAction.SubGroupGuid -SettingGuid $definitions.LidAction.SettingGuid
    }
    catch {
        $lidError = $_.Exception.Message
    }

    $sleep = $null
    $sleepError = $null
    try {
        $sleep = Get-WnsPowerSettingValues -SchemeGuid $scheme -SubGroupGuid $definitions.SleepIdle.SubGroupGuid -SettingGuid $definitions.SleepIdle.SettingGuid
    }
    catch {
        $sleepError = $_.Exception.Message
    }

    $critical = Get-WnsCriticalBatteryPercent -SchemeGuid $scheme
    $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
    $noSystemBattery = (($powerStatus.BatteryChargeStatus -band [System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery) -ne 0)
    $batteryPercent = $null
    if (-not $noSystemBattery -and $powerStatus.BatteryLifePercent -ge 0) {
        $batteryPercent = [int][Math]::Round(([double]$powerStatus.BatteryLifePercent) * 100.0)
    }

    return [pscustomobject][ordered]@{
        CapturedUtc = [DateTime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        OsVersion = [Environment]::OSVersion.VersionString
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Elevated = [bool](Test-WnsCurrentProcessElevated)
        ActiveSchemeGuid = $scheme.ToString()
        Lid = $lid
        LidReadError = $lidError
        SleepIdle = $sleep
        SleepIdleReadError = $sleepError
        CriticalBatteryPercent = $critical
        Power = [pscustomobject][ordered]@{
            HasBattery = (-not $noSystemBattery)
            OnAC = ($powerStatus.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)
            BatteryPercent = $batteryPercent
            ChargeStatus = [string]$powerStatus.BatteryChargeStatus
        }
    }
}

function Save-WnsEvidenceJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Assert-WnsSnapshotSupportsSmoke {
    param([Parameter(Mandatory = $true)][object]$Snapshot)

    if ($null -eq $Snapshot.Lid) {
        throw "Lid action could not be read. No mutation is allowed. $($Snapshot.LidReadError)"
    }
    if ($null -eq $Snapshot.SleepIdle) {
        throw "Sleep idle values could not be read. No mutation is allowed. $($Snapshot.SleepIdleReadError)"
    }
    if ($Snapshot.Elevated) {
        throw 'First product-compatibility mutation proof must run from a non-elevated session. Re-run from the normal Cursor/user terminal.'
    }
    if ($Snapshot.Power.HasBattery -and -not $Snapshot.Power.OnAC) {
        throw 'First mutation smoke must run on AC power. Connect the charger before this bounded write/restore proof.'
    }
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$evidenceRoot = Join-Path $repoRoot 'artifacts\local-verification'
$runDir = Join-Path $evidenceRoot $stamp
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$transactionPaths = Get-WnsRuntimePaths -BasePath (Join-Path $runDir 'transaction')
Initialize-WnsRuntimeStorage -Paths $transactionPaths

$beforePath = Join-Path $runDir 'before.json'
$afterPath = Join-Path $runDir 'after.json'
$resultPath = Join-Path $runDir 'result.json'

$powerCfgActive = Invoke-WnsReadOnlyCommand -FilePath 'powercfg.exe' -Arguments '/getactivescheme'
$powerCfgStates = Invoke-WnsReadOnlyCommand -FilePath 'powercfg.exe' -Arguments '/a'
$powerCfgRequests = Invoke-WnsReadOnlyCommand -FilePath 'powercfg.exe' -Arguments '/requests'
$before = Get-WnsLocalPowerSnapshot
Save-WnsEvidenceJson -Path $beforePath -Value $before

$definitions = Get-WnsPowerPolicyDefinitions
$plan = @()
if ($null -ne $before.Lid -and $null -ne $before.SleepIdle) {
    $plan = @(New-WnsPowerPolicyPlan `
        -SchemeGuid ([Guid]$before.ActiveSchemeGuid) `
        -LidValues $before.Lid `
        -SleepIdleValues $before.SleepIdle `
        -EnableLidProtection $true `
        -EnableDcSleepOverride $true)
}

$summary = [pscustomobject][ordered]@{
    Mode = $Mode
    EvidenceDirectory = $runDir
    Before = $before
    ProposedChanges = $plan
    PowerCfg = [pscustomobject][ordered]@{
        ActiveScheme = $powerCfgActive
        AvailableSleepStates = $powerCfgStates
        Requests = $powerCfgRequests
    }
    MutationAttempted = $false
    MutationApplied = $false
    RestoreAttempted = $false
    RestoreVerified = $false
    Outcome = 'PROBE_ONLY'
    Error = $null
}

if ($Mode -eq 'Probe') {
    Save-WnsEvidenceJson -Path $resultPath -Value $summary
    Write-Host 'LOCAL_WINDOWS_PROBE_COMPLETE'
    Write-Host "Evidence: $runDir"
    Write-Host "Active scheme: $($before.ActiveSchemeGuid)"
    if ($null -ne $before.Lid) {
        Write-Host ("Lid action AC={0} DC={1}" -f $before.Lid.AC, $before.Lid.DC)
    }
    else {
        Write-Warning "Lid action unreadable: $($before.LidReadError)"
    }
    if ($null -ne $before.SleepIdle) {
        Write-Host ("Sleep idle AC={0}s DC={1}s" -f $before.SleepIdle.AC, $before.SleepIdle.DC)
    }
    else {
        Write-Warning "Sleep idle unreadable: $($before.SleepIdleReadError)"
    }
    Write-Host "Critical battery level: $($before.CriticalBatteryPercent)%"
    Write-Host "Proposed temporary changes: $($plan.Count)"
    exit 0
}

if (-not $AcknowledgeTemporaryPowerPolicyChange) {
    throw 'ApplyRestoreSmoke requires -AcknowledgeTemporaryPowerPolicyChange. The default Probe mode never mutates power policy.'
}

Assert-WnsSnapshotSupportsSmoke -Snapshot $before

if ($plan.Count -eq 0) {
    $summary.Outcome = 'NO_CHANGES_NEEDED'
    $summary.RestoreVerified = $true
    $after = Get-WnsLocalPowerSnapshot
    $summary | Add-Member -NotePropertyName After -NotePropertyValue $after
    Save-WnsEvidenceJson -Path $afterPath -Value $after
    Save-WnsEvidenceJson -Path $resultPath -Value $summary
    Write-Host 'LOCAL_WINDOWS_APPLY_RESTORE_SMOKE_COMPLETE: no values required modification.'
    Write-Host "Evidence: $runDir"
    exit 0
}

$summary.MutationAttempted = $true
$transactionStarted = $false
try {
    $started = Start-WnsPowerPolicyTransaction `
        -Paths $transactionPaths `
        -SchemeGuid ([Guid]$before.ActiveSchemeGuid) `
        -Changes $plan

    $transactionStarted = [bool]$started.Active
    $summary.MutationApplied = $transactionStarted

    foreach ($change in $plan) {
        if (-not (Test-WnsPowerPolicyChangeApplied -Change $change)) {
            throw "Post-apply verification failed for $($change.Name)."
        }
    }

    Write-Host 'Temporary policy values applied and verified. Holding for 3 seconds before mandatory restore...'
    Start-Sleep -Seconds 3
    $summary.Outcome = 'APPLIED_VERIFIED_PENDING_RESTORE'
}
catch {
    $summary.Error = $_.Exception.Message
    $summary.Outcome = 'APPLY_FAILED'
    throw
}
finally {
    $summary.RestoreAttempted = $true
    try {
        $restoreResult = Restore-WnsPowerPolicyTransaction -Paths $transactionPaths
        $summary.RestoreVerified = ($restoreResult.Restored -or -not $transactionStarted)
    }
    catch {
        $summary.RestoreVerified = $false
        $restoreMessage = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace([string]$summary.Error)) {
            $summary.Error = $restoreMessage
        }
        else {
            $summary.Error = "$($summary.Error) | RESTORE: $restoreMessage"
        }
        Write-Error "RESTORE FAILED. Do not continue testing. Recovery evidence is at $($transactionPaths.RecoveryPath). $restoreMessage"
    }

    $after = Get-WnsLocalPowerSnapshot
    $summary | Add-Member -NotePropertyName After -NotePropertyValue $after -Force
    Save-WnsEvidenceJson -Path $afterPath -Value $after

    $lidRestored = ($after.ActiveSchemeGuid -eq $before.ActiveSchemeGuid) -and
        ($after.Lid.AC -eq $before.Lid.AC) -and
        ($after.Lid.DC -eq $before.Lid.DC)
    $sleepRestored = ($after.ActiveSchemeGuid -eq $before.ActiveSchemeGuid) -and
        ($after.SleepIdle.AC -eq $before.SleepIdle.AC) -and
        ($after.SleepIdle.DC -eq $before.SleepIdle.DC)

    if ($summary.RestoreVerified -and $lidRestored -and $sleepRestored) {
        $summary.Outcome = 'APPLY_AND_EXACT_RESTORE_VERIFIED'
        $summary.RestoreVerified = $true
    }
    else {
        $summary.Outcome = 'RESTORE_NOT_PROVEN'
        $summary.RestoreVerified = $false
    }

    Save-WnsEvidenceJson -Path $resultPath -Value $summary
}

if (-not $summary.RestoreVerified) {
    throw "Exact restoration was not proven. STOP. Evidence: $runDir"
}

Write-Host 'LOCAL_WINDOWS_APPLY_RESTORE_SMOKE_COMPLETE'
Write-Host 'Exact original lid and sleep-idle values were restored and re-read successfully.'
Write-Host "Evidence: $runDir"
