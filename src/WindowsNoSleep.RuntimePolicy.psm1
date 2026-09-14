Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'WindowsNoSleep.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WindowsNoSleep.PowerPolicy.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WindowsNoSleep.PolicyTransaction.psm1') -Force

function New-WnsRuntimePolicyPlanFromValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter(Mandatory = $true)]
        [bool]$HasBattery,

        [Parameter(Mandatory = $true)]
        [Guid]$SchemeGuid,

        [AllowNull()]
        [object]$LidValues,

        [AllowNull()]
        [object]$SleepIdleValues
    )

    if (-not $HasBattery) {
        return [pscustomobject][ordered]@{
            SchemeGuid = $SchemeGuid
            Changes = @()
            LidProtectionRequested = $false
            DcSleepOverrideRequested = $false
        }
    }

    $enableLid = [bool]$Settings.LidProtection
    $enableDcSleep = [bool]$Settings.ProtectOnBattery

    if ($enableLid -and $null -eq $LidValues) {
        throw 'Lid protection is enabled, but the current lid-close AC/DC policy could not be read.'
    }
    if ($enableDcSleep -and $null -eq $SleepIdleValues) {
        throw 'Battery protection is enabled, but the current idle-sleep AC/DC policy could not be read.'
    }

    $changes = @(New-WnsPowerPolicyPlan `
        -SchemeGuid $SchemeGuid `
        -LidValues $LidValues `
        -SleepIdleValues $SleepIdleValues `
        -EnableLidProtection $enableLid `
        -EnableDcSleepOverride $enableDcSleep)

    return [pscustomobject][ordered]@{
        SchemeGuid = $SchemeGuid
        Changes = $changes
        LidProtectionRequested = $enableLid
        DcSleepOverrideRequested = $enableDcSleep
    }
}

function Get-WnsRuntimePolicyPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter(Mandatory = $true)]
        [bool]$HasBattery
    )

    $scheme = Get-WnsActivePowerSchemeGuid
    if (-not $HasBattery) {
        return New-WnsRuntimePolicyPlanFromValues `
            -Settings $Settings `
            -HasBattery $false `
            -SchemeGuid $scheme `
            -LidValues $null `
            -SleepIdleValues $null
    }

    $definitions = Get-WnsPowerPolicyDefinitions
    $lidValues = $null
    $sleepValues = $null

    if ([bool]$Settings.LidProtection) {
        $lidValues = Get-WnsPowerSettingValues `
            -SchemeGuid $scheme `
            -SubGroupGuid $definitions.LidAction.SubGroupGuid `
            -SettingGuid $definitions.LidAction.SettingGuid
    }

    if ([bool]$Settings.ProtectOnBattery) {
        $sleepValues = Get-WnsPowerSettingValues `
            -SchemeGuid $scheme `
            -SubGroupGuid $definitions.SleepIdle.SubGroupGuid `
            -SettingGuid $definitions.SleepIdle.SettingGuid
    }

    return New-WnsRuntimePolicyPlanFromValues `
        -Settings $Settings `
        -HasBattery $HasBattery `
        -SchemeGuid $scheme `
        -LidValues $lidValues `
        -SleepIdleValues $sleepValues
}

function Get-WnsRuntimeBatterySafetyThreshold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Settings
    )

    $critical = $null
    try {
        $critical = Get-WnsCriticalBatteryPercent
    }
    catch {
        $critical = $null
    }

    return Get-WnsEffectiveBatterySafetyThreshold `
        -BasePercent ([int]$Settings.BatterySafetyPercent) `
        -WindowsCriticalPercent $critical
}

function Restore-WnsRuntimePolicyIfPending {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths
    )

    $status = Get-WnsRecoveryStatus -Paths $Paths
    switch ($status.Status) {
        'None' {
            return [pscustomobject][ordered]@{
                Restored = $false
                ChangeCount = 0
                PreviousSchemeGuid = $null
            }
        }
        'Corrupt' {
            throw "Power-policy recovery data is corrupt. Refusing to continue until it is repaired: $($status.Error)"
        }
        'Pending' {
            $scheme = [string]$status.Snapshot.SchemeGuid
            $restored = Restore-WnsPowerPolicyTransaction -Paths $Paths
            return [pscustomobject][ordered]@{
                Restored = [bool]$restored.Restored
                ChangeCount = [int]$restored.ChangeCount
                PreviousSchemeGuid = $scheme
            }
        }
        default {
            throw "Unexpected power-policy recovery state: $($status.Status)"
        }
    }
}

function Start-WnsRuntimePolicyProtection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths,

        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter(Mandatory = $true)]
        [bool]$HasBattery
    )

    $pending = Get-WnsRecoveryStatus -Paths $Paths
    if ($pending.Status -ne 'None') {
        throw "Cannot start a new runtime power-policy transaction while recovery state is $($pending.Status)."
    }

    $plan = Get-WnsRuntimePolicyPlan -Settings $Settings -HasBattery $HasBattery
    if ($plan.Changes.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Active = $false
            ChangeCount = 0
            SchemeGuid = $plan.SchemeGuid
            Changes = @()
        }
    }

    $started = Start-WnsPowerPolicyTransaction `
        -Paths $Paths `
        -SchemeGuid ([Guid]$plan.SchemeGuid) `
        -Changes @($plan.Changes)

    return [pscustomobject][ordered]@{
        Active = [bool]$started.Active
        ChangeCount = [int]$started.ChangeCount
        SchemeGuid = $plan.SchemeGuid
        Changes = @($plan.Changes)
    }
}

function Reset-WnsRuntimePolicyProtection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths,

        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter(Mandatory = $true)]
        [bool]$HasBattery
    )

    [void](Restore-WnsRuntimePolicyIfPending -Paths $Paths)
    return Start-WnsRuntimePolicyProtection -Paths $Paths -Settings $Settings -HasBattery $HasBattery
}

function Sync-WnsRuntimePolicyProtection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths,

        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter(Mandatory = $true)]
        [bool]$HasBattery
    )

    $status = Get-WnsRecoveryStatus -Paths $Paths
    if ($status.Status -eq 'Corrupt') {
        throw "Power-policy recovery data became corrupt while protection was active: $($status.Error)"
    }

    if ($status.Status -eq 'None') {
        return [pscustomobject][ordered]@{
            Rebound = $false
            Active = $false
            ChangeCount = 0
            Reason = 'No temporary policy transaction is active.'
        }
    }

    $snapshotScheme = [Guid]$status.Snapshot.SchemeGuid
    $activeScheme = Get-WnsActivePowerSchemeGuid
    if ($snapshotScheme -eq $activeScheme) {
        return [pscustomobject][ordered]@{
            Rebound = $false
            Active = $true
            ChangeCount = @($status.Snapshot.Changes).Count
            Reason = 'Temporary policy remains bound to the active scheme.'
        }
    }

    # Restore the old scheme values without re-activating that old scheme, then
    # bind a fresh transaction to the plan the user actually switched to.
    [void](Restore-WnsRuntimePolicyIfPending -Paths $Paths)
    $started = Start-WnsRuntimePolicyProtection -Paths $Paths -Settings $Settings -HasBattery $HasBattery

    return [pscustomobject][ordered]@{
        Rebound = $true
        Active = [bool]$started.Active
        ChangeCount = [int]$started.ChangeCount
        Reason = "Active power scheme changed from $snapshotScheme to $activeScheme; runtime policy was rebound."
    }
}

Export-ModuleMember -Function @(
    'New-WnsRuntimePolicyPlanFromValues',
    'Get-WnsRuntimePolicyPlan',
    'Get-WnsRuntimeBatterySafetyThreshold',
    'Restore-WnsRuntimePolicyIfPending',
    'Start-WnsRuntimePolicyProtection',
    'Reset-WnsRuntimePolicyProtection',
    'Sync-WnsRuntimePolicyProtection'
)
