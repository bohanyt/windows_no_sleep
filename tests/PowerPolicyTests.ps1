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
$modulePath = Join-Path $repoRoot 'src\WindowsNoSleep.PowerPolicy.psm1'
Import-Module $modulePath -Force

Write-Host 'Checking documented power-setting identities...'
$definitions = Get-WnsPowerPolicyDefinitions
Assert-Wns ($definitions.LidAction.SettingGuid.ToString() -eq '5ca83367-6e45-459f-a27b-476b1d01c936') 'Unexpected lid action GUID.'
Assert-Wns ($definitions.SleepIdle.SettingGuid.ToString() -eq '29f6c1db-86da-48c5-9fdb-f2b67b1f44da') 'Unexpected sleep idle GUID.'
Assert-Wns ($definitions.HibernateIdle.SettingGuid.ToString() -eq '9d7815a6-7ee4-497e-8888-515a05f02364') 'Unexpected hibernate idle GUID.'
Assert-Wns ($definitions.CriticalBatteryLevel.SettingGuid.ToString() -eq '9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469') 'Unexpected critical battery level GUID.'

Write-Host 'Checking pure temporary-policy planning...'
$scheme = [Guid]'381b4222-f694-41f0-9685-ff5bb260df2e'
$lidValues = [pscustomobject]@{ AC = [uint32]1; DC = [uint32]2 }
$sleepValues = [pscustomobject]@{ AC = [uint32]0; DC = [uint32]1200 }
$plan = @(New-WnsPowerPolicyPlan -SchemeGuid $scheme -LidValues $lidValues -SleepIdleValues $sleepValues -EnableLidProtection $true -EnableDcSleepOverride $true)
Assert-Wns ($plan.Count -eq 2) 'Expected separate lid and DC sleep plan entries.'

$lidChange = @($plan | Where-Object { $_.Name -eq 'LidAction' })
Assert-Wns ($lidChange.Count -eq 1) 'Missing lid plan entry.'
Assert-Wns ($lidChange[0].ApplyAC -eq $true -and $lidChange[0].ApplyDC -eq $true) 'Lid plan must restore/override both non-zero AC and DC actions.'
Assert-Wns ($lidChange[0].TargetAC -eq 0 -and $lidChange[0].TargetDC -eq 0) 'Lid plan target must be Do Nothing (0).'
Assert-Wns ($lidChange[0].OriginalAC -eq 1 -and $lidChange[0].OriginalDC -eq 2) 'Lid plan must preserve exact originals.'

$sleepChange = @($plan | Where-Object { $_.Name -eq 'SleepIdle' })
Assert-Wns ($sleepChange.Count -eq 1) 'Missing DC sleep plan entry.'
Assert-Wns ($sleepChange[0].ApplyAC -eq $false -and $sleepChange[0].ApplyDC -eq $true) 'Sleep plan must not rewrite AC by default.'
Assert-Wns ($sleepChange[0].TargetDC -eq 0) 'DC sleep target must be Never idle to sleep (0).'
Assert-Wns ($sleepChange[0].OriginalDC -eq 1200) 'DC sleep plan must preserve exact original timeout.'

$emptyPlan = @(New-WnsPowerPolicyPlan -SchemeGuid $scheme -LidValues ([pscustomobject]@{ AC = 0; DC = 0 }) -SleepIdleValues ([pscustomobject]@{ AC = 0; DC = 0 }) -EnableLidProtection $true -EnableDcSleepOverride $true)
Assert-Wns ($emptyPlan.Count -eq 0) 'Already-safe values should not generate redundant mutations.'

Write-Host 'Checking real hosted-Windows read-only power API calls...'
$realScheme = Get-WnsActivePowerSchemeGuid
Assert-Wns ($realScheme -ne [Guid]::Empty) 'PowerGetActiveScheme returned an empty GUID.'
Write-Host "Active scheme: $realScheme"

$realSleep = Get-WnsPowerSettingValues -SchemeGuid $realScheme -SubGroupGuid $definitions.SleepIdle.SubGroupGuid -SettingGuid $definitions.SleepIdle.SettingGuid
Assert-Wns ($realSleep.AC -ge 0 -and $realSleep.DC -ge 0) 'Could not read real sleep idle values.'
Write-Host ("Sleep idle AC={0}s DC={1}s" -f $realSleep.AC, $realSleep.DC)

$critical = Get-WnsCriticalBatteryPercent -SchemeGuid $realScheme
if ($null -eq $critical) {
    Write-Host 'Critical battery threshold is unavailable on this hosted runner, which is acceptable for a non-battery machine.'
}
else {
    Assert-Wns ($critical -ge 0 -and $critical -le 100) 'Critical battery threshold is outside 0..100.'
    Write-Host "Critical battery threshold: $critical%"
}

Write-Host 'Checking that -WhatIf never writes policy...'
$dryRunChange = [pscustomobject]@{
    Name = 'SleepIdle'
    SchemeGuid = $realScheme.ToString()
    SubGroupGuid = $definitions.SleepIdle.SubGroupGuid.ToString()
    SettingGuid = $definitions.SleepIdle.SettingGuid.ToString()
    OriginalAC = [uint32]$realSleep.AC
    OriginalDC = [uint32]$realSleep.DC
    TargetAC = [uint32]$realSleep.AC
    TargetDC = [uint32]0
    ApplyAC = $false
    ApplyDC = $true
}
Set-WnsPowerPolicyChange -Change $dryRunChange -WhatIf
$realSleepAfter = Get-WnsPowerSettingValues -SchemeGuid $realScheme -SubGroupGuid $definitions.SleepIdle.SubGroupGuid -SettingGuid $definitions.SleepIdle.SettingGuid
Assert-Wns ($realSleepAfter.AC -eq $realSleep.AC -and $realSleepAfter.DC -eq $realSleep.DC) '-WhatIf changed a real power-setting value.'

Write-Host 'POWER_POLICY_READ_ONLY tests passed. No power-plan value was intentionally changed.'
