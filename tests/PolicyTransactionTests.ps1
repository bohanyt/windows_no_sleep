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

function New-FakeChange {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [uint32]$OriginalAC,
        [uint32]$OriginalDC,
        [uint32]$TargetAC,
        [uint32]$TargetDC,
        [bool]$ApplyAC,
        [bool]$ApplyDC
    )

    return [pscustomobject][ordered]@{
        Name = $Name
        SchemeGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
        SubGroupGuid = '11111111-1111-1111-1111-111111111111'
        SettingGuid = [Guid]::NewGuid().ToString()
        OriginalAC = $OriginalAC
        OriginalDC = $OriginalDC
        TargetAC = $TargetAC
        TargetDC = $TargetDC
        ApplyAC = $ApplyAC
        ApplyDC = $ApplyDC
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$corePath = Join-Path $repoRoot 'src\WindowsNoSleep.Core.psm1'
$transactionPath = Join-Path $repoRoot 'src\WindowsNoSleep.PolicyTransaction.psm1'
# Import the transaction module first; it owns nested imports. Re-import Core
# afterwards so its helpers are explicitly visible to this test script scope.
Import-Module $transactionPath -Force
Import-Module $corePath -Force

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('WindowsNoSleep.TransactionTests.' + [Guid]::NewGuid().ToString('N'))
try {
    $paths = Get-WnsRuntimePaths -BasePath $tempRoot
    Initialize-WnsRuntimeStorage -Paths $paths
    $scheme = [Guid]'381b4222-f694-41f0-9685-ff5bb260df2e'

    Write-Host 'Checking write-ahead snapshot, apply, verification, and exact restore...'
    $changes = @(
        (New-FakeChange -Name 'LidAction' -OriginalAC 1 -OriginalDC 1 -TargetAC 0 -TargetDC 0 -ApplyAC $true -ApplyDC $true),
        (New-FakeChange -Name 'SleepIdle' -OriginalAC 0 -OriginalDC 1200 -TargetAC 0 -TargetDC 0 -ApplyAC $false -ApplyDC $true)
    )

    $state = @{
        LidAction = [pscustomobject]@{ AC = [uint32]1; DC = [uint32]1 }
        SleepIdle = [pscustomobject]@{ AC = [uint32]0; DC = [uint32]1200 }
    }
    $observer = [pscustomobject]@{ SnapshotSeenBeforeFirstApply = $false }
    $applyAction = {
        param($Change, [bool]$RestoreOriginal)
        if (-not $RestoreOriginal -and -not $observer.SnapshotSeenBeforeFirstApply) {
            $observer.SnapshotSeenBeforeFirstApply = (Test-Path -LiteralPath $paths.RecoveryPath)
        }
        $entry = $state[[string]$Change.Name]
        if ([bool]$Change.ApplyAC) {
            $entry.AC = if ($RestoreOriginal) { [uint32]$Change.OriginalAC } else { [uint32]$Change.TargetAC }
        }
        if ([bool]$Change.ApplyDC) {
            $entry.DC = if ($RestoreOriginal) { [uint32]$Change.OriginalDC } else { [uint32]$Change.TargetDC }
        }
    }.GetNewClosure()
    $verifyAction = {
        param($Change, [bool]$ExpectOriginal)
        $entry = $state[[string]$Change.Name]
        $expectedAc = if ($ExpectOriginal) { [uint32]$Change.OriginalAC } else { [uint32]$Change.TargetAC }
        $expectedDc = if ($ExpectOriginal) { [uint32]$Change.OriginalDC } else { [uint32]$Change.TargetDC }
        $acOk = (-not [bool]$Change.ApplyAC) -or ($entry.AC -eq $expectedAc)
        $dcOk = (-not [bool]$Change.ApplyDC) -or ($entry.DC -eq $expectedDc)
        return ($acOk -and $dcOk)
    }.GetNewClosure()

    $started = Start-WnsPowerPolicyTransaction -Paths $paths -SchemeGuid $scheme -Changes $changes -ApplyChange $applyAction -VerifyChange $verifyAction
    Assert-Wns $observer.SnapshotSeenBeforeFirstApply 'Recovery snapshot must exist before the first policy mutation callback.'
    Assert-Wns ($started.Active -and $started.ChangeCount -eq 2) 'Successful transaction result is wrong.'
    Assert-Wns ($state.LidAction.AC -eq 0 -and $state.LidAction.DC -eq 0) 'Lid target was not applied.'
    Assert-Wns ($state.SleepIdle.DC -eq 0) 'DC sleep target was not applied.'
    Assert-Wns ((Get-WnsRecoveryStatus -Paths $paths).Status -eq 'Pending') 'Snapshot must stay pending while temporary overrides are active.'

    $restored = Restore-WnsPowerPolicyTransaction -Paths $paths -ApplyChange $applyAction -VerifyChange $verifyAction
    Assert-Wns ($restored.Restored -and $restored.ChangeCount -eq 2) 'Restore result is wrong.'
    Assert-Wns ($state.LidAction.AC -eq 1 -and $state.LidAction.DC -eq 1) 'Lid originals were not restored exactly.'
    Assert-Wns ($state.SleepIdle.DC -eq 1200) 'Sleep original was not restored exactly.'
    Assert-Wns ((Get-WnsRecoveryStatus -Paths $paths).Status -eq 'None') 'Snapshot must clear only after verified restore.'

    Write-Host 'Checking apply failure rolls back all possibly touched entries...'
    $state.LidAction.AC = 1; $state.LidAction.DC = 1; $state.SleepIdle.DC = 1200
    $applyCounter = [pscustomobject]@{ Value = 0 }
    $failingApply = {
        param($Change, [bool]$RestoreOriginal)
        if (-not $RestoreOriginal) {
            $applyCounter.Value++
        }
        $entry = $state[[string]$Change.Name]
        if ([bool]$Change.ApplyAC) {
            $entry.AC = if ($RestoreOriginal) { [uint32]$Change.OriginalAC } else { [uint32]$Change.TargetAC }
        }
        if ([bool]$Change.ApplyDC) {
            $entry.DC = if ($RestoreOriginal) { [uint32]$Change.OriginalDC } else { [uint32]$Change.TargetDC }
        }
        if (-not $RestoreOriginal -and $applyCounter.Value -eq 2) {
            throw 'synthetic apply failure after possible partial write'
        }
    }.GetNewClosure()

    $applyFailureThrown = $false
    try {
        [void](Start-WnsPowerPolicyTransaction -Paths $paths -SchemeGuid $scheme -Changes $changes -ApplyChange $failingApply -VerifyChange $verifyAction)
    }
    catch {
        $applyFailureThrown = $true
        Assert-Wns ($_.Exception.Message -match 'rolled back successfully') 'Successful rollback should be reported honestly.'
    }
    Assert-Wns $applyFailureThrown 'Synthetic apply failure must surface.'
    Assert-Wns ($state.LidAction.AC -eq 1 -and $state.LidAction.DC -eq 1 -and $state.SleepIdle.DC -eq 1200) 'Apply failure did not restore exact originals.'
    Assert-Wns ((Get-WnsRecoveryStatus -Paths $paths).Status -eq 'None') 'Recovery should clear after a fully verified rollback.'

    Write-Host 'Checking incomplete rollback preserves recovery snapshot...'
    $state.LidAction.AC = 1; $state.LidAction.DC = 1; $state.SleepIdle.DC = 1200
    $brokenRestore = {
        param($Change, [bool]$RestoreOriginal)
        $entry = $state[[string]$Change.Name]
        if ($RestoreOriginal -and [string]$Change.Name -eq 'LidAction') {
            throw 'synthetic restore failure'
        }
        if ([bool]$Change.ApplyAC) {
            $entry.AC = if ($RestoreOriginal) { [uint32]$Change.OriginalAC } else { [uint32]$Change.TargetAC }
        }
        if ([bool]$Change.ApplyDC) {
            $entry.DC = if ($RestoreOriginal) { [uint32]$Change.OriginalDC } else { [uint32]$Change.TargetDC }
        }
    }.GetNewClosure()

    [void](Start-WnsPowerPolicyTransaction -Paths $paths -SchemeGuid $scheme -Changes $changes -ApplyChange $applyAction -VerifyChange $verifyAction)
    $restoreFailureThrown = $false
    try {
        [void](Restore-WnsPowerPolicyTransaction -Paths $paths -ApplyChange $brokenRestore -VerifyChange $verifyAction)
    }
    catch {
        $restoreFailureThrown = $true
    }
    Assert-Wns $restoreFailureThrown 'Incomplete restore must throw.'
    Assert-Wns ((Get-WnsRecoveryStatus -Paths $paths).Status -eq 'Pending') 'Incomplete restore must preserve the recovery snapshot.'

    # Finish cleanup with the healthy fake provider so the test temp state is clean.
    [void](Restore-WnsPowerPolicyTransaction -Paths $paths -ApplyChange $applyAction -VerifyChange $verifyAction)

    Write-Host 'Checking pending/corrupt recovery fails closed...'
    $snapshot = New-WnsRecoverySnapshot -SchemeGuid $scheme.ToString() -Changes $changes
    Write-WnsRecoverySnapshot -Paths $paths -Snapshot $snapshot
    $pendingBlocked = $false
    try {
        [void](Start-WnsPowerPolicyTransaction -Paths $paths -SchemeGuid $scheme -Changes $changes -ApplyChange $applyAction -VerifyChange $verifyAction)
    }
    catch {
        $pendingBlocked = $true
    }
    Assert-Wns $pendingBlocked 'A pending snapshot must block a new transaction.'
    [void](Restore-WnsPowerPolicyTransaction -Paths $paths -ApplyChange $applyAction -VerifyChange $verifyAction)

    [System.IO.File]::WriteAllText($paths.RecoveryPath, '{ corrupt recovery')
    $corruptBlocked = $false
    try {
        [void](Start-WnsPowerPolicyTransaction -Paths $paths -SchemeGuid $scheme -Changes $changes -ApplyChange $applyAction -VerifyChange $verifyAction)
    }
    catch {
        $corruptBlocked = $true
    }
    Assert-Wns $corruptBlocked 'Corrupt recovery data must block a new transaction.'

    Write-Host 'POLICY_TRANSACTION tests passed without mutating Windows power policy.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
