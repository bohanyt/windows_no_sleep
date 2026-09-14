Set-StrictMode -Version Latest

$script:WnsAppName = 'WindowsNoSleep'
$script:WnsSettingsVersion = 1
$script:WnsRecoveryVersion = 1

function Get-WnsDefaultSettings {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        Version                 = $script:WnsSettingsVersion
        KeepComputerAwake       = $true
        ProtectOnBattery        = $true
        LidProtection           = $true
        BlockRestart            = $true
        StartWithWindows        = $false
        KeepDisplayOn           = $false
        BatterySafetyPercent    = 15
    }
}

function ConvertTo-WnsSettings {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$InputObject
    )

    $defaults = Get-WnsDefaultSettings
    if ($null -eq $InputObject) {
        return $defaults
    }

    foreach ($property in $defaults.PSObject.Properties) {
        $incoming = $InputObject.PSObject.Properties[$property.Name]
        if ($null -eq $incoming) {
            continue
        }

        switch ($property.Name) {
            'Version' {
                $defaults.Version = $script:WnsSettingsVersion
            }
            'BatterySafetyPercent' {
                $value = 15
                if ([int]::TryParse([string]$incoming.Value, [ref]$value)) {
                    $defaults.BatterySafetyPercent = [Math]::Min(50, [Math]::Max(5, $value))
                }
            }
            default {
                if ($property.Value -is [bool]) {
                    $parsed = $false
                    if ($incoming.Value -is [bool]) {
                        $parsed = [bool]$incoming.Value
                    }
                    elseif ([bool]::TryParse([string]$incoming.Value, [ref]$parsed)) {
                        # parsed by TryParse
                    }
                    else {
                        continue
                    }
                    $defaults.($property.Name) = $parsed
                }
            }
        }
    }

    return $defaults
}

function Get-WnsRuntimePaths {
    [CmdletBinding()]
    param(
        [string]$BasePath
    )

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $BasePath = Join-Path $env:LOCALAPPDATA $script:WnsAppName
        }
        else {
            $BasePath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) $script:WnsAppName
        }
    }

    return [pscustomobject][ordered]@{
        BasePath      = $BasePath
        SettingsPath  = Join-Path $BasePath 'settings.json'
        RecoveryPath  = Join-Path $BasePath 'recovery.json'
        LogPath       = Join-Path $BasePath 'events.log'
    }
}

function Initialize-WnsRuntimeStorage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.BasePath)) {
        New-Item -ItemType Directory -Path $Paths.BasePath -Force | Out-Null
    }
}

function Write-WnsJsonAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value,

        [int]$Depth = 8
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporaryPath = '{0}.tmp.{1}.{2}' -f $Path, $PID, ([Guid]::NewGuid().ToString('N'))
    try {
        $json = $Value | ConvertTo-Json -Depth $Depth
        [System.IO.File]::WriteAllText(
            $temporaryPath,
            $json,
            (New-Object System.Text.UTF8Encoding($false))
        )
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-WnsSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.SettingsPath)) {
        return Get-WnsDefaultSettings
    }

    try {
        $raw = Get-Content -LiteralPath $Paths.SettingsPath -Raw -ErrorAction Stop
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        return ConvertTo-WnsSettings -InputObject $parsed
    }
    catch {
        return Get-WnsDefaultSettings
    }
}

function Save-WnsSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths,

        [Parameter(Mandatory = $true)]
        [object]$Settings
    )

    $normalized = ConvertTo-WnsSettings -InputObject $Settings
    Write-WnsJsonAtomic -Path $Paths.SettingsPath -Value $normalized
    return $normalized
}

function Write-WnsLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [int]$MaxBytes = 1048576
    )

    try {
        Initialize-WnsRuntimeStorage -Paths $Paths

        if ((Test-Path -LiteralPath $Paths.LogPath) -and ((Get-Item -LiteralPath $Paths.LogPath).Length -ge $MaxBytes)) {
            $oldPath = '{0}.1' -f $Paths.LogPath
            Remove-Item -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $Paths.LogPath -Destination $oldPath -Force
        }

        $line = '{0} [{1}] {2}' -f ([DateTime]::UtcNow.ToString('o')), $Level, $Message
        Add-Content -LiteralPath $Paths.LogPath -Value $line -Encoding UTF8
    }
    catch {
        # Logging must never prevent cleanup or shutdown of the app.
    }
}

function Get-WnsEffectiveBatterySafetyThreshold {
    [CmdletBinding()]
    param(
        [int]$BasePercent = 15,
        [Nullable[int]]$WindowsCriticalPercent
    )

    $effective = [Math]::Min(50, [Math]::Max(5, $BasePercent))

    # Windows PowerShell 5.1 unwraps a non-null Nullable[int] argument to
    # System.Int32, so do not depend on Nullable<T>.HasValue here.
    if ($null -ne $WindowsCriticalPercent) {
        $candidate = ([int]$WindowsCriticalPercent) + 5
        if ($candidate -gt $effective) {
            $effective = $candidate
        }
    }

    return [Math]::Min(50, [Math]::Max(5, $effective))
}

function New-WnsState {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        Status       = 'STARTING'
        Previous     = $null
        Reason       = 'Process starting'
        ChangedUtc   = [DateTime]::UtcNow.ToString('o')
    }
}

function Test-WnsStateTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$From,

        [Parameter(Mandatory = $true)]
        [string]$To
    )

    if ($From -eq $To) {
        return $true
    }

    $allowed = @{
        'STARTING' = @('RECOVERING_PREVIOUS_STATE', 'PROTECTED', 'DEGRADED', 'BATTERY_SAFETY', 'STOPPED', 'EXITING')
        'RECOVERING_PREVIOUS_STATE' = @('PROTECTED', 'DEGRADED', 'BATTERY_SAFETY', 'STOPPED', 'EXITING')
        'PROTECTED' = @('DEGRADED', 'BATTERY_SAFETY', 'STOPPED', 'EXITING')
        'DEGRADED' = @('PROTECTED', 'BATTERY_SAFETY', 'STOPPED', 'EXITING')
        'BATTERY_SAFETY' = @('PROTECTED', 'DEGRADED', 'STOPPED', 'EXITING')
        'STOPPED' = @('PROTECTED', 'DEGRADED', 'BATTERY_SAFETY', 'EXITING')
        'EXITING' = @()
    }

    if (-not $allowed.ContainsKey($From)) {
        return $false
    }

    return ($allowed[$From] -contains $To)
}

function Set-WnsState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Reason = ''
    )

    if (-not (Test-WnsStateTransition -From $State.Status -To $Status)) {
        throw "Invalid WindowsNoSleep state transition: $($State.Status) -> $Status"
    }

    $previous = $State.Status
    $State.Previous = $previous
    $State.Status = $Status
    $State.Reason = $Reason
    $State.ChangedUtc = [DateTime]::UtcNow.ToString('o')
    return $State
}

function New-WnsRecoverySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SchemeGuid,

        [Parameter(Mandatory = $true)]
        [object[]]$Changes
    )

    return [pscustomobject][ordered]@{
        Version         = $script:WnsRecoveryVersion
        RestoreRequired = $true
        CreatedUtc      = [DateTime]::UtcNow.ToString('o')
        SchemeGuid      = $SchemeGuid
        Changes         = @($Changes)
    }
}

function Write-WnsRecoverySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths,

        [Parameter(Mandatory = $true)]
        [object]$Snapshot
    )

    Write-WnsJsonAtomic -Path $Paths.RecoveryPath -Value $Snapshot
}

function Get-WnsRecoveryStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.RecoveryPath)) {
        return [pscustomobject]@{
            Status = 'None'
            Snapshot = $null
            Error = $null
        }
    }

    try {
        $raw = Get-Content -LiteralPath $Paths.RecoveryPath -Raw -ErrorAction Stop
        $snapshot = $raw | ConvertFrom-Json -ErrorAction Stop

        if ($null -eq $snapshot.Version -or $null -eq $snapshot.RestoreRequired -or $null -eq $snapshot.SchemeGuid -or $null -eq $snapshot.Changes) {
            throw 'Recovery snapshot is missing required fields.'
        }

        return [pscustomobject]@{
            Status = 'Pending'
            Snapshot = $snapshot
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Status = 'Corrupt'
            Snapshot = $null
            Error = $_.Exception.Message
        }
    }
}

function Clear-WnsRecoverySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths
    )

    Remove-Item -LiteralPath $Paths.RecoveryPath -Force -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function @(
    'Get-WnsDefaultSettings',
    'ConvertTo-WnsSettings',
    'Get-WnsRuntimePaths',
    'Initialize-WnsRuntimeStorage',
    'Write-WnsJsonAtomic',
    'Get-WnsSettings',
    'Save-WnsSettings',
    'Write-WnsLog',
    'Get-WnsEffectiveBatterySafetyThreshold',
    'New-WnsState',
    'Test-WnsStateTransition',
    'Set-WnsState',
    'New-WnsRecoverySnapshot',
    'Write-WnsRecoverySnapshot',
    'Get-WnsRecoveryStatus',
    'Clear-WnsRecoverySnapshot'
)
