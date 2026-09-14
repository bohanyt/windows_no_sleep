Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WnsGuidSystemButtons = [Guid]'4f971e89-eebd-4455-a8de-9e59040e7347'
$script:WnsGuidLidAction = [Guid]'5ca83367-6e45-459f-a27b-476b1d01c936'
$script:WnsGuidSleep = [Guid]'238c9fa8-0aad-41ed-83f4-97be242c8f20'
$script:WnsGuidSleepIdle = [Guid]'29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
$script:WnsGuidHibernateIdle = [Guid]'9d7815a6-7ee4-497e-8888-515a05f02364'
$script:WnsGuidBattery = [Guid]'e73a048d-bf27-4f12-9731-8b2076e8891f'
$script:WnsGuidCriticalBatteryLevel = [Guid]'9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469'

if (-not ('WindowsNoSleep.PowerPolicy.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WindowsNoSleep.PowerPolicy
{
    public static class Native
    {
        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern UInt32 PowerGetActiveScheme(IntPtr UserRootPowerKey, out IntPtr ActivePolicyGuid);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern UInt32 PowerReadACValueIndex(
            IntPtr RootPowerKey,
            ref Guid SchemeGuid,
            ref Guid SubGroupOfPowerSettingsGuid,
            ref Guid PowerSettingGuid,
            out UInt32 AcValueIndex);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern UInt32 PowerReadDCValueIndex(
            IntPtr RootPowerKey,
            ref Guid SchemeGuid,
            ref Guid SubGroupOfPowerSettingsGuid,
            ref Guid PowerSettingGuid,
            out UInt32 DcValueIndex);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern UInt32 PowerWriteACValueIndex(
            IntPtr RootPowerKey,
            ref Guid SchemeGuid,
            ref Guid SubGroupOfPowerSettingsGuid,
            ref Guid PowerSettingGuid,
            UInt32 AcValueIndex);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern UInt32 PowerWriteDCValueIndex(
            IntPtr RootPowerKey,
            ref Guid SchemeGuid,
            ref Guid SubGroupOfPowerSettingsGuid,
            ref Guid PowerSettingGuid,
            UInt32 DcValueIndex);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern UInt32 PowerSetActiveScheme(IntPtr UserRootPowerKey, ref Guid SchemeGuid);

        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr hMem);

        private static void ThrowIfError(UInt32 result, string operation)
        {
            if (result != 0)
            {
                throw new Win32Exception(unchecked((int)result), operation + " failed");
            }
        }

        public static Guid GetActiveScheme()
        {
            IntPtr pointer;
            UInt32 result = PowerGetActiveScheme(IntPtr.Zero, out pointer);
            ThrowIfError(result, "PowerGetActiveScheme");
            if (pointer == IntPtr.Zero)
            {
                throw new InvalidOperationException("PowerGetActiveScheme returned a null GUID pointer.");
            }

            try
            {
                return (Guid)Marshal.PtrToStructure(pointer, typeof(Guid));
            }
            finally
            {
                LocalFree(pointer);
            }
        }

        public static UInt32 ReadAc(Guid scheme, Guid subgroup, Guid setting)
        {
            UInt32 value;
            UInt32 result = PowerReadACValueIndex(IntPtr.Zero, ref scheme, ref subgroup, ref setting, out value);
            ThrowIfError(result, "PowerReadACValueIndex");
            return value;
        }

        public static UInt32 ReadDc(Guid scheme, Guid subgroup, Guid setting)
        {
            UInt32 value;
            UInt32 result = PowerReadDCValueIndex(IntPtr.Zero, ref scheme, ref subgroup, ref setting, out value);
            ThrowIfError(result, "PowerReadDCValueIndex");
            return value;
        }

        public static void WriteAc(Guid scheme, Guid subgroup, Guid setting, UInt32 value)
        {
            UInt32 result = PowerWriteACValueIndex(IntPtr.Zero, ref scheme, ref subgroup, ref setting, value);
            ThrowIfError(result, "PowerWriteACValueIndex");
        }

        public static void WriteDc(Guid scheme, Guid subgroup, Guid setting, UInt32 value)
        {
            UInt32 result = PowerWriteDCValueIndex(IntPtr.Zero, ref scheme, ref subgroup, ref setting, value);
            ThrowIfError(result, "PowerWriteDCValueIndex");
        }

        public static void Activate(Guid scheme)
        {
            UInt32 result = PowerSetActiveScheme(IntPtr.Zero, ref scheme);
            ThrowIfError(result, "PowerSetActiveScheme");
        }
    }
}
'@
}

function Get-WnsPowerPolicyDefinitions {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        LidAction = [pscustomobject][ordered]@{
            Name = 'LidAction'
            SubGroupGuid = $script:WnsGuidSystemButtons
            SettingGuid = $script:WnsGuidLidAction
        }
        SleepIdle = [pscustomobject][ordered]@{
            Name = 'SleepIdle'
            SubGroupGuid = $script:WnsGuidSleep
            SettingGuid = $script:WnsGuidSleepIdle
        }
        HibernateIdle = [pscustomobject][ordered]@{
            Name = 'HibernateIdle'
            SubGroupGuid = $script:WnsGuidSleep
            SettingGuid = $script:WnsGuidHibernateIdle
        }
        CriticalBatteryLevel = [pscustomobject][ordered]@{
            Name = 'CriticalBatteryLevel'
            SubGroupGuid = $script:WnsGuidBattery
            SettingGuid = $script:WnsGuidCriticalBatteryLevel
        }
    }
}

function Get-WnsActivePowerSchemeGuid {
    [CmdletBinding()]
    param()

    return [WindowsNoSleep.PowerPolicy.Native]::GetActiveScheme()
}

function Get-WnsPowerSettingValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Guid]$SchemeGuid,

        [Parameter(Mandatory = $true)]
        [Guid]$SubGroupGuid,

        [Parameter(Mandatory = $true)]
        [Guid]$SettingGuid
    )

    $ac = [WindowsNoSleep.PowerPolicy.Native]::ReadAc($SchemeGuid, $SubGroupGuid, $SettingGuid)
    $dc = [WindowsNoSleep.PowerPolicy.Native]::ReadDc($SchemeGuid, $SubGroupGuid, $SettingGuid)

    return [pscustomobject][ordered]@{
        AC = [uint32]$ac
        DC = [uint32]$dc
    }
}

function Get-WnsCriticalBatteryPercent {
    [CmdletBinding()]
    param(
        [Nullable[Guid]]$SchemeGuid
    )

    try {
        $scheme = if ($null -eq $SchemeGuid) { Get-WnsActivePowerSchemeGuid } else { [Guid]$SchemeGuid }
        $definitions = Get-WnsPowerPolicyDefinitions
        $values = Get-WnsPowerSettingValues -SchemeGuid $scheme -SubGroupGuid $definitions.CriticalBatteryLevel.SubGroupGuid -SettingGuid $definitions.CriticalBatteryLevel.SettingGuid
        return [int]$values.DC
    }
    catch {
        # Desktops/NUCs and managed images may not expose a meaningful battery setting.
        # Battery Safety remains conservative by using the configured base threshold.
        return $null
    }
}

function New-WnsPowerPolicyPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Guid]$SchemeGuid,

        [AllowNull()]
        [object]$LidValues,

        [AllowNull()]
        [object]$SleepIdleValues,

        [bool]$EnableLidProtection = $true,

        [bool]$EnableDcSleepOverride = $false
    )

    $definitions = Get-WnsPowerPolicyDefinitions
    $changes = @()

    if ($EnableLidProtection -and $null -ne $LidValues) {
        $applyAc = ([uint32]$LidValues.AC -ne 0)
        $applyDc = ([uint32]$LidValues.DC -ne 0)
        if ($applyAc -or $applyDc) {
            $changes += [pscustomobject][ordered]@{
                Name = 'LidAction'
                SchemeGuid = $SchemeGuid.ToString()
                SubGroupGuid = $definitions.LidAction.SubGroupGuid.ToString()
                SettingGuid = $definitions.LidAction.SettingGuid.ToString()
                OriginalAC = [uint32]$LidValues.AC
                OriginalDC = [uint32]$LidValues.DC
                TargetAC = [uint32]0
                TargetDC = [uint32]0
                ApplyAC = $applyAc
                ApplyDC = $applyDc
            }
        }
    }

    if ($EnableDcSleepOverride -and $null -ne $SleepIdleValues) {
        # Sleep idle value 0 is documented as Never idle to sleep. We only plan a
        # DC override here; AC can rely on the normal SystemRequired request.
        $applyDc = ([uint32]$SleepIdleValues.DC -ne 0)
        if ($applyDc) {
            $changes += [pscustomobject][ordered]@{
                Name = 'SleepIdle'
                SchemeGuid = $SchemeGuid.ToString()
                SubGroupGuid = $definitions.SleepIdle.SubGroupGuid.ToString()
                SettingGuid = $definitions.SleepIdle.SettingGuid.ToString()
                OriginalAC = [uint32]$SleepIdleValues.AC
                OriginalDC = [uint32]$SleepIdleValues.DC
                TargetAC = [uint32]$SleepIdleValues.AC
                TargetDC = [uint32]0
                ApplyAC = $false
                ApplyDC = $true
            }
        }
    }

    return @($changes)
}

function Set-WnsPowerPolicyChange {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Change,

        [switch]$RestoreOriginal
    )

    $scheme = [Guid]$Change.SchemeGuid
    $subgroup = [Guid]$Change.SubGroupGuid
    $setting = [Guid]$Change.SettingGuid
    $ac = if ($RestoreOriginal) { [uint32]$Change.OriginalAC } else { [uint32]$Change.TargetAC }
    $dc = if ($RestoreOriginal) { [uint32]$Change.OriginalDC } else { [uint32]$Change.TargetDC }
    $verb = if ($RestoreOriginal) { 'restore' } else { 'apply temporary override to' }

    if (-not $RestoreOriginal) {
        $activeBefore = Get-WnsActivePowerSchemeGuid
        if ($activeBefore -ne $scheme) {
            throw "Refusing temporary power-policy mutation because active scheme changed from snapshot $scheme to $activeBefore."
        }
    }

    if ($PSCmdlet.ShouldProcess("$($Change.Name) in scheme $scheme", $verb)) {
        if ([bool]$Change.ApplyAC) {
            [WindowsNoSleep.PowerPolicy.Native]::WriteAc($scheme, $subgroup, $setting, $ac)
        }
        if ([bool]$Change.ApplyDC) {
            [WindowsNoSleep.PowerPolicy.Native]::WriteDc($scheme, $subgroup, $setting, $dc)
        }

        # PowerSetActiveScheme is required to apply writes to the active scheme,
        # but it must never switch the user back to a plan they changed to while
        # Windows No Sleep was running. Restoration may safely write values back
        # into the old (now inactive) scheme without activating it.
        $activeAfterWrite = Get-WnsActivePowerSchemeGuid
        if ($activeAfterWrite -eq $scheme) {
            [WindowsNoSleep.PowerPolicy.Native]::Activate($scheme)
        }
        elseif (-not $RestoreOriginal) {
            throw "Active power scheme changed during temporary override; values were written only to snapshot scheme $scheme and it was not re-activated."
        }
    }
}

function Test-WnsPowerPolicyChangeApplied {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Change,

        [switch]$ExpectOriginal
    )

    $scheme = [Guid]$Change.SchemeGuid
    $subgroup = [Guid]$Change.SubGroupGuid
    $setting = [Guid]$Change.SettingGuid
    $current = Get-WnsPowerSettingValues -SchemeGuid $scheme -SubGroupGuid $subgroup -SettingGuid $setting

    $expectedAc = if ($ExpectOriginal) { [uint32]$Change.OriginalAC } else { [uint32]$Change.TargetAC }
    $expectedDc = if ($ExpectOriginal) { [uint32]$Change.OriginalDC } else { [uint32]$Change.TargetDC }

    $acOk = (-not [bool]$Change.ApplyAC) -or ([uint32]$current.AC -eq $expectedAc)
    $dcOk = (-not [bool]$Change.ApplyDC) -or ([uint32]$current.DC -eq $expectedDc)
    return ($acOk -and $dcOk)
}

Export-ModuleMember -Function @(
    'Get-WnsPowerPolicyDefinitions',
    'Get-WnsActivePowerSchemeGuid',
    'Get-WnsPowerSettingValues',
    'Get-WnsCriticalBatteryPercent',
    'New-WnsPowerPolicyPlan',
    'Set-WnsPowerPolicyChange',
    'Test-WnsPowerPolicyChangeApplied'
)
