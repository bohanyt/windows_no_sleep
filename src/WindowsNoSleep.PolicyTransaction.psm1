Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Nested modules must not force-reload dependencies because Windows PowerShell
# 5.1 can remove commands that were already imported into the caller's scope.
Import-Module (Join-Path $PSScriptRoot 'WindowsNoSleep.Core.psm1')
Import-Module (Join-Path $PSScriptRoot 'WindowsNoSleep.PowerPolicy.psm1')

function New-WnsDefaultPolicyApplyAction {
    [CmdletBinding()]
    param()

    return {
        param($Change, [bool]$RestoreOriginal)
        if ($RestoreOriginal) {
            Set-WnsPowerPolicyChange -Change $Change -RestoreOriginal -Confirm:$false
        }
        else {
            Set-WnsPowerPolicyChange -Change $Change -Confirm:$false
        }
    }
}

function New-WnsDefaultPolicyVerifyAction {
    [CmdletBinding()]
    param()

    return {
        param($Change, [bool]$ExpectOriginal)
        if ($ExpectOriginal) {
            return [bool](Test-WnsPowerPolicyChangeApplied -Change $Change -ExpectOriginal)
        }
        return [bool](Test-WnsPowerPolicyChangeApplied -Change $Change)
    }
}

function Assert-WnsNoPendingPolicyTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths
    )

    $status = Get-WnsRecoveryStatus -Paths $Paths
    switch ($status.Status) {
        'None' { return }
        'Pending' {
            throw 'A previous power-policy recovery snapshot is still pending. Restore it before starting a new transaction.'
        }
        'Corrupt' {
            throw "Power-policy recovery snapshot is corrupt. Refusing new mutations: $($status.Error)"
        }
        default {
            throw "Unexpected power-policy recovery status: $($status.Status)"
        }
    }
}

function Restore-WnsPolicyChangesInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Changes,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ApplyChange,

        [Parameter(Mandatory = $true)]
        [scriptblock]$VerifyChange
    )

    $errors = @()
    for ($index = $Changes.Count - 1; $index -ge 0; $index--) {
        $change = $Changes[$index]
        try {
            & $ApplyChange $change $true
            if (-not [bool](& $VerifyChange $change $true)) {
                throw "Original values could not be verified for $($change.Name)."
            }
        }
        catch {
            $errors += [pscustomobject][ordered]@{
                Name = [string]$change.Name
                Error = $_.Exception.Message
            }
        }
    }

    return @($errors)
}

function Start-WnsPowerPolicyTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths,

        [Parameter(Mandatory = $true)]
        [Guid]$SchemeGuid,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Changes,

        [scriptblock]$ApplyChange,

        [scriptblock]$VerifyChange
    )

    if ($null -eq $ApplyChange) {
        $ApplyChange = New-WnsDefaultPolicyApplyAction
    }
    if ($null -eq $VerifyChange) {
        $VerifyChange = New-WnsDefaultPolicyVerifyAction
    }

    Assert-WnsNoPendingPolicyTransaction -Paths $Paths

    if ($Changes.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Active = $false
            ChangeCount = 0
            RollbackRequired = $false
        }
    }

    # This persistent snapshot is the write-ahead record. No Windows policy
    # mutation is allowed before it has been durably written.
    $snapshot = New-WnsRecoverySnapshot -SchemeGuid $SchemeGuid.ToString() -Changes $Changes
    Write-WnsRecoverySnapshot -Paths $Paths -Snapshot $snapshot

    $attempted = @()
    try {
        foreach ($change in $Changes) {
            # Include the current entry before invoking the provider. A provider
            # can fail after a partial native write, so rollback must include it.
            $attempted += $change
            & $ApplyChange $change $false
            if (-not [bool](& $VerifyChange $change $false)) {
                throw "Temporary values could not be verified for $($change.Name)."
            }
        }

        return [pscustomobject][ordered]@{
            Active = $true
            ChangeCount = $Changes.Count
            RollbackRequired = $true
        }
    }
    catch {
        $originalError = $_.Exception.Message
        # PowerShell unwraps an empty function result to $null; force an array so
        # strict-mode Count checks are deterministic on Windows PowerShell 5.1.
        $rollbackErrors = @(Restore-WnsPolicyChangesInternal -Changes $attempted -ApplyChange $ApplyChange -VerifyChange $VerifyChange)
        if ($rollbackErrors.Count -eq 0) {
            Clear-WnsRecoverySnapshot -Paths $Paths
            throw "Power-policy transaction failed and was rolled back successfully: $originalError"
        }

        $detail = ($rollbackErrors | ForEach-Object { "$($_.Name): $($_.Error)" }) -join '; '
        throw "Power-policy transaction failed and rollback is incomplete. Recovery snapshot was preserved. Original error: $originalError. Rollback: $detail"
    }
}

function Restore-WnsPowerPolicyTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Paths,

        [scriptblock]$ApplyChange,

        [scriptblock]$VerifyChange
    )

    if ($null -eq $ApplyChange) {
        $ApplyChange = New-WnsDefaultPolicyApplyAction
    }
    if ($null -eq $VerifyChange) {
        $VerifyChange = New-WnsDefaultPolicyVerifyAction
    }

    $status = Get-WnsRecoveryStatus -Paths $Paths
    switch ($status.Status) {
        'None' {
            return [pscustomobject][ordered]@{
                Restored = $false
                ChangeCount = 0
            }
        }
        'Corrupt' {
            throw "Power-policy recovery snapshot is corrupt and cannot be restored automatically: $($status.Error)"
        }
        'Pending' {
            # Continue below.
        }
        default {
            throw "Unexpected power-policy recovery status: $($status.Status)"
        }
    }

    $changes = @($status.Snapshot.Changes)
    $restoreErrors = @(Restore-WnsPolicyChangesInternal -Changes $changes -ApplyChange $ApplyChange -VerifyChange $VerifyChange)
    if ($restoreErrors.Count -gt 0) {
        $detail = ($restoreErrors | ForEach-Object { "$($_.Name): $($_.Error)" }) -join '; '
        throw "Power-policy restore is incomplete. Recovery snapshot was preserved: $detail"
    }

    Clear-WnsRecoverySnapshot -Paths $Paths
    return [pscustomobject][ordered]@{
        Restored = $true
        ChangeCount = $changes.Count
    }
}

Export-ModuleMember -Function @(
    'Assert-WnsNoPendingPolicyTransaction',
    'Start-WnsPowerPolicyTransaction',
    'Restore-WnsPowerPolicyTransaction'
)
