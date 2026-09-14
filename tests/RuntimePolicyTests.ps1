#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Wns {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$corePath = Join-Path $repoRoot 'src\WindowsNoSleep.Core.psm1'
$runtimePath = Join-Path $repoRoot 'src\WindowsNoSleep.RuntimePolicy.psm1'

Import-Module $runtimePath -Force
Import-Module $corePath -Force

$settings = Get-WnsDefaultSettings
$scheme = [Guid]'381b4222-f694-41f0-9685-ff5bb260df2e'

Write-Host 'Checking no-battery systems never receive lid/DC plan mutations...'
$desktopPlan = New-WnsRuntimePolicyPlanFromValues `
    -Settings $settings `
    -HasBattery $false `
    -SchemeGuid $scheme `
    -LidValues $null `
    -SleepIdleValues $null
Assert-Wns ($desktopPlan.Changes.Count -eq 0) 'No-battery systems must not receive laptop power-policy changes.'

Write-Host 'Checking the verified owner-laptop snapshot plans only DC idle-sleep override...'
$ownerPlan = New-WnsRuntimePolicyPlanFromValues `
    -Settings $settings `
    -HasBattery $true `
    -SchemeGuid $scheme `
    -LidValues ([pscustomobject]@{ AC = [uint32]0; DC = [uint32]0 }) `
    -SleepIdleValues ([pscustomobject]@{ AC = [uint32]0; DC = [uint32]1200 })
Assert-Wns ($ownerPlan.Changes.Count -eq 1) 'Owner-laptop baseline should produce exactly one temporary change.'
$ownerChange = $ownerPlan.Changes[0]
Assert-Wns ($ownerChange.Name -eq 'SleepIdle') 'Owner-laptop change must be SleepIdle only.'
Assert-Wns (-not [bool]$ownerChange.ApplyAC) 'Owner-laptop sleep change must not touch AC.'
Assert-Wns ([bool]$ownerChange.ApplyDC) 'Owner-laptop sleep change must touch DC.'
Assert-Wns ([uint32]$ownerChange.OriginalDC -eq 1200) 'Owner-laptop original DC sleep must be preserved.'
Assert-Wns ([uint32]$ownerChange.TargetDC -eq 0) 'Owner-laptop target DC sleep must be Never (0).'

Write-Host 'Checking a laptop whose lid currently sleeps gets bounded lid plus DC sleep changes...'
$genericLaptopPlan = New-WnsRuntimePolicyPlanFromValues `
    -Settings $settings `
    -HasBattery $true `
    -SchemeGuid $scheme `
    -LidValues ([pscustomobject]@{ AC = [uint32]1; DC = [uint32]1 }) `
    -SleepIdleValues ([pscustomobject]@{ AC = [uint32]900; DC = [uint32]1200 })
Assert-Wns ($genericLaptopPlan.Changes.Count -eq 2) 'Generic laptop should plan LidAction and DC SleepIdle changes.'
$lidChange = @($genericLaptopPlan.Changes | Where-Object { $_.Name -eq 'LidAction' })[0]
$sleepChange = @($genericLaptopPlan.Changes | Where-Object { $_.Name -eq 'SleepIdle' })[0]
Assert-Wns ([bool]$lidChange.ApplyAC -and [bool]$lidChange.ApplyDC) 'Lid protection must cover AC and DC when originals are not Do Nothing.'
Assert-Wns ([uint32]$lidChange.TargetAC -eq 0 -and [uint32]$lidChange.TargetDC -eq 0) 'Lid target must be Do Nothing.'
Assert-Wns (-not [bool]$sleepChange.ApplyAC -and [bool]$sleepChange.ApplyDC) 'Sleep override must remain DC-only.'
Assert-Wns ([uint32]$sleepChange.TargetAC -eq 900) 'AC sleep value must be preserved in the change record.'

Write-Host 'Checking settings remove only their corresponding policy responsibilities...'
$settingsNoBattery = Get-WnsDefaultSettings
$settingsNoBattery.ProtectOnBattery = $false
$lidOnlyPlan = New-WnsRuntimePolicyPlanFromValues `
    -Settings $settingsNoBattery `
    -HasBattery $true `
    -SchemeGuid $scheme `
    -LidValues ([pscustomobject]@{ AC = [uint32]1; DC = [uint32]1 }) `
    -SleepIdleValues $null
Assert-Wns ($lidOnlyPlan.Changes.Count -eq 1 -and $lidOnlyPlan.Changes[0].Name -eq 'LidAction') 'Disabling battery protection must remove the DC sleep override without disabling lid protection.'

$settingsNoLid = Get-WnsDefaultSettings
$settingsNoLid.LidProtection = $false
$sleepOnlyPlan = New-WnsRuntimePolicyPlanFromValues `
    -Settings $settingsNoLid `
    -HasBattery $true `
    -SchemeGuid $scheme `
    -LidValues $null `
    -SleepIdleValues ([pscustomobject]@{ AC = [uint32]0; DC = [uint32]1200 })
Assert-Wns ($sleepOnlyPlan.Changes.Count -eq 1 -and $sleepOnlyPlan.Changes[0].Name -eq 'SleepIdle') 'Disabling lid protection must leave battery sleep protection independent.'

Write-Host 'Checking unreadable policy fails closed when its feature is requested...'
$missingLidThrown = $false
try {
    [void](New-WnsRuntimePolicyPlanFromValues `
        -Settings $settings `
        -HasBattery $true `
        -SchemeGuid $scheme `
        -LidValues $null `
        -SleepIdleValues ([pscustomobject]@{ AC = 0; DC = 1200 }))
}
catch { $missingLidThrown = $true }
Assert-Wns $missingLidThrown 'Requested lid protection must not silently proceed without readable originals.'

Write-Host 'Checking real hosted-Windows no-battery lifecycle remains non-mutating...'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('WindowsNoSleep.RuntimePolicy.' + [Guid]::NewGuid().ToString('N'))
try {
    $paths = Get-WnsRuntimePaths -BasePath $tempRoot
    Initialize-WnsRuntimeStorage -Paths $paths

    $started = Start-WnsRuntimePolicyProtection -Paths $paths -Settings $settings -HasBattery $false
    Assert-Wns (-not $started.Active) 'No-battery hosted runtime policy must have no active transaction.'
    Assert-Wns ($started.ChangeCount -eq 0) 'No-battery hosted runtime policy must have zero changes.'
    Assert-Wns ((Get-WnsRecoveryStatus -Paths $paths).Status -eq 'None') 'No-battery lifecycle must not create recovery state.'

    $restored = Restore-WnsRuntimePolicyIfPending -Paths $paths
    Assert-Wns (-not $restored.Restored) 'No pending transaction should report no restore.'

    $threshold = Get-WnsRuntimeBatterySafetyThreshold -Settings $settings
    Assert-Wns ($threshold -ge 15 -and $threshold -le 50) 'Runtime battery threshold must respect configured/OEM safety bounds.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'RUNTIME_POLICY tests passed.'
