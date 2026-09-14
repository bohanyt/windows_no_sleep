#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Wns {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$appPath = Join-Path $repoRoot 'WindowsNoSleep.ps1'
$corePath = Join-Path $repoRoot 'src\WindowsNoSleep.Core.psm1'

Write-Host 'Checking PowerShell parser errors...'
foreach ($path in @($appPath, $corePath)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $messages = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join [Environment]::NewLine
        throw "Parser errors in $path`:$([Environment]::NewLine)$messages"
    }
}

Import-Module $corePath -Force

Write-Host 'Checking defaults...'
$defaults = Get-WnsDefaultSettings
Assert-Wns ($defaults.KeepComputerAwake -eq $true) 'Protection must default ON.'
Assert-Wns ($defaults.ProtectOnBattery -eq $true) 'Battery protection must default ON.'
Assert-Wns ($defaults.LidProtection -eq $true) 'Lid protection preference must default ON.'
Assert-Wns ($defaults.BlockRestart -eq $true) 'Restart guard must default ON.'
Assert-Wns ($defaults.KeepDisplayOn -eq $false) 'Display forcing must default OFF.'
Assert-Wns ($defaults.StartWithWindows -eq $false) 'Autostart must default OFF.'
Assert-Wns ($defaults.BatterySafetyPercent -eq 15) 'Battery Safety base threshold must default to 15%.'

Write-Host 'Checking settings normalization...'
$normalized = ConvertTo-WnsSettings -InputObject ([pscustomobject]@{
    KeepComputerAwake = $false
    KeepDisplayOn = $true
    BatterySafetyPercent = 99
})
Assert-Wns ($normalized.KeepComputerAwake -eq $false) 'Boolean settings must round-trip.'
Assert-Wns ($normalized.KeepDisplayOn -eq $true) 'Display option must normalize.'
Assert-Wns ($normalized.BatterySafetyPercent -eq 50) 'Battery Safety setting must clamp to the documented maximum.'
Assert-Wns ($normalized.ProtectOnBattery -eq $true) 'Missing settings must retain safe defaults.'

Write-Host 'Checking effective battery threshold...'
Assert-Wns ((Get-WnsEffectiveBatterySafetyThreshold -BasePercent 15) -eq 15) 'Base threshold calculation failed.'
Assert-Wns ((Get-WnsEffectiveBatterySafetyThreshold -BasePercent 15 -WindowsCriticalPercent 20) -eq 25) 'Critical+5 threshold calculation failed.'
Assert-Wns ((Get-WnsEffectiveBatterySafetyThreshold -BasePercent 1) -eq 5) 'Minimum clamp failed.'
Assert-Wns ((Get-WnsEffectiveBatterySafetyThreshold -BasePercent 90) -eq 50) 'Maximum clamp failed.'

Write-Host 'Checking state machine...'
$state = New-WnsState
Assert-Wns ($state.Status -eq 'STARTING') 'Initial state must be STARTING.'
$state = Set-WnsState -State $state -Status 'PROTECTED' -Reason 'test'
Assert-Wns ($state.Status -eq 'PROTECTED') 'STARTING -> PROTECTED must be valid.'
Assert-Wns ((Test-WnsStateTransition -From 'PROTECTED' -To 'BATTERY_SAFETY') -eq $true) 'Protected -> Battery Safety must be valid.'
Assert-Wns ((Test-WnsStateTransition -From 'EXITING' -To 'PROTECTED') -eq $false) 'EXITING must be terminal.'

$invalidTransitionThrown = $false
try {
    [void](Set-WnsState -State $state -Status 'STARTING' -Reason 'invalid')
}
catch {
    $invalidTransitionThrown = $true
}
Assert-Wns $invalidTransitionThrown 'Invalid state transition must throw.'

Write-Host 'Checking settings/recovery persistence in a temp directory...'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('WindowsNoSleep.Tests.' + [Guid]::NewGuid().ToString('N'))
try {
    $paths = Get-WnsRuntimePaths -BasePath $tempRoot
    Initialize-WnsRuntimeStorage -Paths $paths

    $saved = Get-WnsDefaultSettings
    $saved.BatterySafetyPercent = 19
    [void](Save-WnsSettings -Paths $paths -Settings $saved)
    $loaded = Get-WnsSettings -Paths $paths
    Assert-Wns ($loaded.BatterySafetyPercent -eq 19) 'Settings file did not round-trip.'

    $changes = @(
        [pscustomobject]@{ Setting = 'LidAction'; AC = 1; DC = 1 }
    )
    $snapshot = New-WnsRecoverySnapshot -SchemeGuid '00000000-0000-0000-0000-000000000001' -Changes $changes
    Write-WnsRecoverySnapshot -Paths $paths -Snapshot $snapshot
    $recovery = Get-WnsRecoveryStatus -Paths $paths
    Assert-Wns ($recovery.Status -eq 'Pending') 'Recovery snapshot must be detected as pending.'
    Assert-Wns ($recovery.Snapshot.RestoreRequired -eq $true) 'Recovery snapshot must require restoration.'

    Clear-WnsRecoverySnapshot -Paths $paths
    $cleared = Get-WnsRecoveryStatus -Paths $paths
    Assert-Wns ($cleared.Status -eq 'None') 'Recovery snapshot must clear cleanly.'

    [System.IO.File]::WriteAllText($paths.RecoveryPath, '{ definitely not json')
    $corrupt = Get-WnsRecoveryStatus -Paths $paths
    Assert-Wns ($corrupt.Status -eq 'Corrupt') 'Corrupt recovery data must fail closed.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'STATIC_CHECKED core tests passed.'
