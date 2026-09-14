#requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$RecoveryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'Windows No Sleep'
$script:AppVersion = '0.2.0-dev'
$script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ScriptPath = Join-Path $script:ScriptRoot 'WindowsNoSleep.ps1'

Import-Module (Join-Path $script:ScriptRoot 'src\WindowsNoSleep.Core.psm1') -Force
Import-Module (Join-Path $script:ScriptRoot 'src\WindowsNoSleep.Interop.psm1') -Force
Import-Module (Join-Path $script:ScriptRoot 'src\WindowsNoSleep.RuntimePolicy.psm1') -Force

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:Paths = Get-WnsRuntimePaths
Initialize-WnsRuntimeStorage -Paths $script:Paths
$script:Settings = Get-WnsSettings -Paths $script:Paths
$script:State = New-WnsState
$script:PowerHandle = [IntPtr]::Zero
$script:SystemRequestSet = $false
$script:DisplayRequestSet = $false
$script:ShutdownReasonSet = $false
$script:CoreProtectionActive = $false
$script:UserStopped = $false
$script:Exiting = $false
$script:SettingsForm = $null
$script:NotifyIcon = $null
$script:HostForm = $null
$script:BatteryTimer = $null
$script:OpenTimer = $null
$script:ToggleMenu = $null
$script:Mutex = $null
$script:OpenSettingsEvent = $null

function Get-WnsLastWin32ErrorText {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $message = (New-Object ComponentModel.Win32Exception($code)).Message
    return "Win32 error $code`: $message"
}

function Get-WnsBatterySnapshot {
    $status = [System.Windows.Forms.SystemInformation]::PowerStatus
    $noBattery = (($status.BatteryChargeStatus -band [System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery) -ne 0)
    $percent = $null

    if (-not $noBattery -and $status.BatteryLifePercent -ge 0) {
        $percent = [int][Math]::Round(([double]$status.BatteryLifePercent) * 100.0)
        $percent = [Math]::Min(100, [Math]::Max(0, $percent))
    }

    return [pscustomobject][ordered]@{
        HasBattery = (-not $noBattery)
        OnAC = ($status.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)
        Percent = $percent
        RawStatus = [string]$status.BatteryChargeStatus
    }
}

function Get-WnsBatteryThreshold {
    return Get-WnsRuntimeBatterySafetyThreshold -Settings $script:Settings
}

function Set-WnsRuntimeState {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    $script:State = Set-WnsState -State $script:State -Status $Status -Reason $Reason
    Write-WnsLog -Paths $script:Paths -Message ("State -> {0}: {1}" -f $Status, $Reason)
    Update-WnsTrayState
    Update-WnsSettingsView
}

function Get-WnsRecoveryRunOnceKey {
    return 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
}

function Enable-WnsRecoveryRunOnce {
    $key = Get-WnsRecoveryRunOnceKey
    $command = 'powershell.exe -NoProfile -STA -WindowStyle Hidden -File "{0}" -RecoveryOnly' -f $script:ScriptPath
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name 'WindowsNoSleepRecovery' -Value $command -Type String
}

function Disable-WnsRecoveryRunOnce {
    Remove-ItemProperty -Path (Get-WnsRecoveryRunOnceKey) -Name 'WindowsNoSleepRecovery' -ErrorAction SilentlyContinue
}

function Restore-WnsOwnedPolicy {
    param(
        [string]$Reason = 'runtime cleanup',
        [switch]$ThrowOnFailure
    )

    try {
        $result = Restore-WnsRuntimePolicyIfPending -Paths $script:Paths
        if ($result.Restored) {
            Write-WnsLog -Paths $script:Paths -Message ("Restored {0} temporary power-policy change(s): {1}." -f $result.ChangeCount, $Reason)
        }
        Disable-WnsRecoveryRunOnce
        return [pscustomobject][ordered]@{
            Restored = [bool]$result.Restored
            ChangeCount = [int]$result.ChangeCount
            Error = $null
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-WnsLog -Paths $script:Paths -Level 'ERROR' -Message "Temporary power-policy restore failed ($Reason): $message"
        if ($ThrowOnFailure) {
            throw
        }
        return [pscustomobject][ordered]@{
            Restored = $false
            ChangeCount = 0
            Error = $message
        }
    }
}

function Enable-WnsOwnedPolicy {
    $battery = Get-WnsBatterySnapshot

    if ($battery.HasBattery -and ([bool]$script:Settings.LidProtection -or [bool]$script:Settings.ProtectOnBattery)) {
        # The RunOnce hook is deliberately installed before any policy write.
        # If the process or OS dies after a successful write, the next sign-in
        # has a supported, non-bypass path that attempts exact recovery first.
        Enable-WnsRecoveryRunOnce
    }

    try {
        $result = Reset-WnsRuntimePolicyProtection `
            -Paths $script:Paths `
            -Settings $script:Settings `
            -HasBattery ([bool]$battery.HasBattery)

        if ($result.Active) {
            $names = (@($result.Changes | ForEach-Object { $_.Name }) -join ', ')
            Write-WnsLog -Paths $script:Paths -Message ("Temporary power-policy protection active on scheme {0}: {1}." -f $result.SchemeGuid, $names)
        }
        else {
            Disable-WnsRecoveryRunOnce
        }
        return $result
    }
    catch {
        if ((Get-WnsRecoveryStatus -Paths $script:Paths).Status -eq 'None') {
            Disable-WnsRecoveryRunOnce
        }
        throw
    }
}

function Sync-WnsOwnedPolicy {
    $battery = Get-WnsBatterySnapshot
    if (-not $battery.HasBattery) {
        return
    }

    $result = Sync-WnsRuntimePolicyProtection `
        -Paths $script:Paths `
        -Settings $script:Settings `
        -HasBattery $true

    if ($result.Rebound) {
        if ($result.Active) {
            Enable-WnsRecoveryRunOnce
        }
        else {
            Disable-WnsRecoveryRunOnce
        }
        Write-WnsLog -Paths $script:Paths -Message $result.Reason
    }
}

function New-WnsPowerRequestHandle {
    $context = New-Object WindowsNoSleep.Interop.ReasonContext
    $context.Version = 0
    $context.Flags = 1
    $context.SimpleReasonString = 'Windows No Sleep is keeping this computer available for its running workloads.'

    $handle = [WindowsNoSleep.Interop.NativeMethods]::PowerCreateRequest([ref]$context)
    if ($handle -eq [IntPtr](-1)) {
        throw "PowerCreateRequest failed. $(Get-WnsLastWin32ErrorText)"
    }
    return $handle
}

function Enable-WnsPowerRequests {
    if ($script:PowerHandle -eq [IntPtr]::Zero) {
        $script:PowerHandle = New-WnsPowerRequestHandle
    }

    if (-not $script:SystemRequestSet) {
        if (-not [WindowsNoSleep.Interop.NativeMethods]::PowerSetRequest(
            $script:PowerHandle,
            [WindowsNoSleep.Interop.PowerRequestType]::SystemRequired
        )) {
            throw "PowerSetRequest(SystemRequired) failed. $(Get-WnsLastWin32ErrorText)"
        }
        $script:SystemRequestSet = $true
    }

    if ([bool]$script:Settings.KeepDisplayOn -and -not $script:DisplayRequestSet) {
        if (-not [WindowsNoSleep.Interop.NativeMethods]::PowerSetRequest(
            $script:PowerHandle,
            [WindowsNoSleep.Interop.PowerRequestType]::DisplayRequired
        )) {
            throw "PowerSetRequest(DisplayRequired) failed. $(Get-WnsLastWin32ErrorText)"
        }
        $script:DisplayRequestSet = $true
    }
    elseif (-not [bool]$script:Settings.KeepDisplayOn -and $script:DisplayRequestSet) {
        [void][WindowsNoSleep.Interop.NativeMethods]::PowerClearRequest(
            $script:PowerHandle,
            [WindowsNoSleep.Interop.PowerRequestType]::DisplayRequired
        )
        $script:DisplayRequestSet = $false
    }
}

function Disable-WnsPowerRequests {
    if ($script:PowerHandle -eq [IntPtr]::Zero) {
        return
    }

    if ($script:DisplayRequestSet) {
        [void][WindowsNoSleep.Interop.NativeMethods]::PowerClearRequest($script:PowerHandle, [WindowsNoSleep.Interop.PowerRequestType]::DisplayRequired)
        $script:DisplayRequestSet = $false
    }
    if ($script:SystemRequestSet) {
        [void][WindowsNoSleep.Interop.NativeMethods]::PowerClearRequest($script:PowerHandle, [WindowsNoSleep.Interop.PowerRequestType]::SystemRequired)
        $script:SystemRequestSet = $false
    }
    [void][WindowsNoSleep.Interop.NativeMethods]::CloseHandle($script:PowerHandle)
    $script:PowerHandle = [IntPtr]::Zero
}

function Enable-WnsShutdownGuard {
    if (-not [bool]$script:Settings.BlockRestart) {
        Disable-WnsShutdownGuard
        return
    }

    $script:HostForm.BlockShutdown = $true
    if (-not $script:ShutdownReasonSet) {
        if (-not [WindowsNoSleep.Interop.NativeMethods]::ShutdownBlockReasonCreate(
            $script:HostForm.Handle,
            'Windows No Sleep protection is active. Stop Protection or force the restart if it is intentional.'
        )) {
            $script:HostForm.BlockShutdown = $false
            throw "ShutdownBlockReasonCreate failed. $(Get-WnsLastWin32ErrorText)"
        }
        $script:ShutdownReasonSet = $true
    }
}

function Disable-WnsShutdownGuard {
    if ($null -eq $script:HostForm) {
        return
    }
    $script:HostForm.BlockShutdown = $false
    if ($script:ShutdownReasonSet) {
        [void][WindowsNoSleep.Interop.NativeMethods]::ShutdownBlockReasonDestroy($script:HostForm.Handle)
        $script:ShutdownReasonSet = $false
    }
}

function Test-WnsBatterySafetyRequired {
    $battery = Get-WnsBatterySnapshot
    if (-not $battery.HasBattery -or $battery.OnAC) {
        return $false
    }
    if (-not [bool]$script:Settings.ProtectOnBattery) {
        return $true
    }
    if ($null -eq $battery.Percent) {
        return $false
    }
    return ($battery.Percent -le (Get-WnsBatteryThreshold))
}

function Enter-WnsBatterySafety {
    $battery = Get-WnsBatterySnapshot
    $restore = Restore-WnsOwnedPolicy -Reason 'Battery Safety'

    Disable-WnsShutdownGuard
    Disable-WnsPowerRequests
    $script:CoreProtectionActive = $false

    $reason = if (-not [bool]$script:Settings.ProtectOnBattery) {
        'Battery protection is disabled by settings; normal Windows power policy is restored.'
    }
    elseif ($null -ne $battery.Percent) {
        "Battery is $($battery.Percent)% (safety threshold $(Get-WnsBatteryThreshold)%); normal Windows power policy is restored."
    }
    else {
        'Battery Safety requested; normal Windows power policy is restored.'
    }

    if ($null -ne $restore.Error) {
        $reason += " WARNING: temporary policy restore failed: $($restore.Error)"
    }

    if ($script:State.Status -ne 'BATTERY_SAFETY') {
        Set-WnsRuntimeState -Status 'BATTERY_SAFETY' -Reason $reason
    }
}

function Start-WnsProtection {
    param([switch]$AutomaticResume)

    if (-not [bool]$script:Settings.KeepComputerAwake) {
        Stop-WnsProtection -Reason 'Protection disabled in settings.'
        return
    }

    if (Test-WnsBatterySafetyRequired) {
        Enter-WnsBatterySafety
        return
    }

    try {
        Enable-WnsPowerRequests
        Enable-WnsShutdownGuard
        $script:CoreProtectionActive = $true
    }
    catch {
        Disable-WnsShutdownGuard
        Disable-WnsPowerRequests
        $script:CoreProtectionActive = $false
        Set-WnsRuntimeState -Status 'DEGRADED' -Reason $_.Exception.Message
        return
    }

    if (-not $AutomaticResume) {
        $script:UserStopped = $false
    }

    try {
        $policy = Enable-WnsOwnedPolicy
        $detail = if ($policy.Active) {
            "System power request is active; $($policy.ChangeCount) temporary power-policy change(s) are protected by exact recovery."
        }
        else {
            'System power request is active; no temporary power-policy change is required on this machine.'
        }
        Set-WnsRuntimeState -Status 'PROTECTED' -Reason $detail
    }
    catch {
        Write-WnsLog -Paths $script:Paths -Level 'ERROR' -Message "Runtime power-policy protection unavailable: $($_.Exception.Message)"
        Set-WnsRuntimeState -Status 'DEGRADED' -Reason "System power request is active, but temporary lid/battery policy protection is unavailable: $($_.Exception.Message)"
    }
}

function Stop-WnsProtection {
    param(
        [string]$Reason = 'Protection stopped by operator.',
        [switch]$UserInitiated
    )

    $restore = Restore-WnsOwnedPolicy -Reason $Reason
    Disable-WnsShutdownGuard
    Disable-WnsPowerRequests
    $script:CoreProtectionActive = $false

    if ($UserInitiated) {
        $script:UserStopped = $true
    }

    if ($null -ne $restore.Error) {
        $Reason += " WARNING: temporary policy restore failed: $($restore.Error)"
    }

    if ($script:State.Status -ne 'STOPPED' -and $script:State.Status -ne 'EXITING') {
        Set-WnsRuntimeState -Status 'STOPPED' -Reason $Reason
    }
}

function Set-WnsAutostart {
    param([Parameter(Mandatory = $true)][bool]$Enabled)

    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($Enabled) {
        $command = 'powershell.exe -NoProfile -STA -WindowStyle Hidden -File "{0}"' -f $script:ScriptPath
        New-Item -Path $key -Force | Out-Null
        Set-ItemProperty -Path $key -Name 'WindowsNoSleep' -Value $command -Type String
    }
    else {
        Remove-ItemProperty -Path $key -Name 'WindowsNoSleep' -ErrorAction SilentlyContinue
    }
}

function Update-WnsTrayState {
    if ($null -eq $script:NotifyIcon) {
        return
    }

    $battery = Get-WnsBatterySnapshot
    $powerText = if ($battery.OnAC) { 'AC' } elseif ($battery.HasBattery) { 'Battery' } else { 'No battery' }

    switch ($script:State.Status) {
        'PROTECTED' {
            $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
            $text = "Windows No Sleep - Protected ($powerText)"
        }
        'BATTERY_SAFETY' {
            $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Warning
            $text = 'Windows No Sleep - Battery Safety'
        }
        'DEGRADED' {
            $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Warning
            $text = 'Windows No Sleep - Degraded'
        }
        'STOPPED' {
            $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
            $text = 'Windows No Sleep - Stopped'
        }
        default {
            $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
            $text = "Windows No Sleep - $($script:State.Status)"
        }
    }

    if ($text.Length -gt 63) { $text = $text.Substring(0, 63) }
    $script:NotifyIcon.Text = $text

    if ($null -ne $script:ToggleMenu) {
        $script:ToggleMenu.Text = if ($script:State.Status -eq 'PROTECTED' -or $script:State.Status -eq 'DEGRADED') {
            'Stop Protection'
        }
        else {
            'Start Protection'
        }
    }
}

function Update-WnsSettingsView {
    if ($null -eq $script:SettingsForm -or $script:SettingsForm.IsDisposed) {
        return
    }

    $script:SettingsForm.Controls['StatusLabel'].Text = "Status: $($script:State.Status)"
    $script:SettingsForm.Controls['DetailLabel'].Text = $script:State.Reason

    $battery = Get-WnsBatterySnapshot
    if ($battery.HasBattery -and $null -ne $battery.Percent) {
        $source = if ($battery.OnAC) { 'AC' } else { 'Battery' }
        $script:SettingsForm.Controls['BatteryLabel'].Text = "Power: $source | Battery: $($battery.Percent)% | Safety: $(Get-WnsBatteryThreshold)%"
    }
    else {
        $script:SettingsForm.Controls['BatteryLabel'].Text = 'Power: no system battery detected'
    }

    $recovery = Get-WnsRecoveryStatus -Paths $script:Paths
    $script:SettingsForm.Controls['PolicyLabel'].Text = switch ($recovery.Status) {
        'Pending' { "Temporary policy: active ($(@($recovery.Snapshot.Changes).Count) change(s), exact restore armed)" }
        'Corrupt' { 'Temporary policy: RECOVERY DATA CORRUPT' }
        default { 'Temporary policy: none required / fully restored' }
    }

    $script:SettingsForm.Controls['StartStopButton'].Text = if ($script:State.Status -eq 'PROTECTED' -or $script:State.Status -eq 'DEGRADED') {
        'Stop Protection'
    }
    else {
        'Start Protection'
    }
}

function Save-WnsSettingsFromForm {
    if ($null -eq $script:SettingsForm) { return }

    $oldAutostart = [bool]$script:Settings.StartWithWindows
    $script:Settings.KeepComputerAwake = [bool]$script:SettingsForm.Controls['KeepComputerAwake'].Checked
    $script:Settings.ProtectOnBattery = [bool]$script:SettingsForm.Controls['ProtectOnBattery'].Checked
    $script:Settings.LidProtection = [bool]$script:SettingsForm.Controls['LidProtection'].Checked
    $script:Settings.BlockRestart = [bool]$script:SettingsForm.Controls['BlockRestart'].Checked
    $script:Settings.StartWithWindows = [bool]$script:SettingsForm.Controls['StartWithWindows'].Checked
    $script:Settings.KeepDisplayOn = [bool]$script:SettingsForm.Controls['KeepDisplayOn'].Checked
    $script:Settings.BatterySafetyPercent = [int]$script:SettingsForm.Controls['BatterySafetyPercent'].Value
    $script:Settings = Save-WnsSettings -Paths $script:Paths -Settings $script:Settings

    if ($oldAutostart -ne [bool]$script:Settings.StartWithWindows) {
        try {
            Set-WnsAutostart -Enabled ([bool]$script:Settings.StartWithWindows)
        }
        catch {
            Write-WnsLog -Paths $script:Paths -Level 'ERROR' -Message "Autostart update failed: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show(
                "Could not change Start with Windows.`r`n`r`n$($_.Exception.Message)",
                $script:AppName,
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    }

    if ([bool]$script:Settings.KeepComputerAwake) {
        Start-WnsProtection
    }
    else {
        Stop-WnsProtection -Reason 'Protection disabled in settings.' -UserInitiated
    }
    Update-WnsSettingsView
}

function New-WnsSettingsForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Name = 'SettingsForm'
    $form.Text = "$($script:AppName) $($script:AppVersion)"
    $form.Width = 450
    $form.Height = 535
    $form.MinimumSize = New-Object System.Drawing.Size(450, 535)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $true

    $status = New-Object System.Windows.Forms.Label
    $status.Name = 'StatusLabel'; $status.Left = 20; $status.Top = 20; $status.Width = 390; $status.Height = 25
    $status.Font = New-Object System.Drawing.Font($status.Font, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($status)

    $detail = New-Object System.Windows.Forms.Label
    $detail.Name = 'DetailLabel'; $detail.Left = 20; $detail.Top = 48; $detail.Width = 390; $detail.Height = 58
    $form.Controls.Add($detail)

    $battery = New-Object System.Windows.Forms.Label
    $battery.Name = 'BatteryLabel'; $battery.Left = 20; $battery.Top = 108; $battery.Width = 390; $battery.Height = 22
    $form.Controls.Add($battery)

    $policy = New-Object System.Windows.Forms.Label
    $policy.Name = 'PolicyLabel'; $policy.Left = 20; $policy.Top = 132; $policy.Width = 390; $policy.Height = 35
    $form.Controls.Add($policy)

    $items = @(
        @('KeepComputerAwake', 'Keep computer awake', 170, [bool]$script:Settings.KeepComputerAwake),
        @('ProtectOnBattery', 'Protect on battery', 200, [bool]$script:Settings.ProtectOnBattery),
        @('LidProtection', 'Keep running with lid closed', 230, [bool]$script:Settings.LidProtection),
        @('BlockRestart', 'Block normal automatic restart/shutdown', 260, [bool]$script:Settings.BlockRestart),
        @('KeepDisplayOn', 'Keep display on (normally leave OFF)', 290, [bool]$script:Settings.KeepDisplayOn),
        @('StartWithWindows', 'Start with Windows', 320, [bool]$script:Settings.StartWithWindows)
    )
    foreach ($item in $items) {
        $box = New-Object System.Windows.Forms.CheckBox
        $box.Name = $item[0]; $box.Text = $item[1]; $box.Left = 20; $box.Top = $item[2]; $box.Width = 390; $box.Checked = $item[3]
        $form.Controls.Add($box)
    }

    $thresholdLabel = New-Object System.Windows.Forms.Label
    $thresholdLabel.Text = 'Battery Safety threshold:'; $thresholdLabel.Left = 20; $thresholdLabel.Top = 360; $thresholdLabel.Width = 190
    $form.Controls.Add($thresholdLabel)

    $threshold = New-Object System.Windows.Forms.NumericUpDown
    $threshold.Name = 'BatterySafetyPercent'; $threshold.Left = 215; $threshold.Top = 357; $threshold.Width = 65
    $threshold.Minimum = 5; $threshold.Maximum = 50; $threshold.Value = [decimal]$script:Settings.BatterySafetyPercent
    $form.Controls.Add($threshold)

    $percent = New-Object System.Windows.Forms.Label
    $percent.Text = '%'; $percent.Left = 285; $percent.Top = 360; $percent.Width = 30
    $form.Controls.Add($percent)

    $save = New-Object System.Windows.Forms.Button
    $save.Text = 'Apply Settings'; $save.Left = 20; $save.Top = 400; $save.Width = 120; $save.Height = 30
    $save.add_Click({ Save-WnsSettingsFromForm })
    $form.Controls.Add($save)

    $startStop = New-Object System.Windows.Forms.Button
    $startStop.Name = 'StartStopButton'; $startStop.Left = 150; $startStop.Top = 400; $startStop.Width = 125; $startStop.Height = 30
    $startStop.add_Click({
        if ($script:State.Status -eq 'PROTECTED' -or $script:State.Status -eq 'DEGRADED') {
            Stop-WnsProtection -UserInitiated
        }
        else {
            $script:Settings.KeepComputerAwake = $true
            $script:Settings = Save-WnsSettings -Paths $script:Paths -Settings $script:Settings
            $script:UserStopped = $false
            Start-WnsProtection
        }
    })
    $form.Controls.Add($startStop)

    $exit = New-Object System.Windows.Forms.Button
    $exit.Text = 'Exit'; $exit.Left = 285; $exit.Top = 400; $exit.Width = 125; $exit.Height = 30
    $exit.add_Click({ Exit-WnsApplication })
    $form.Controls.Add($exit)

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Display may turn off. Temporary lid/DC sleep changes are snapshotted before write and restored on Stop, Battery Safety, Exit, next launch, or recovery RunOnce.'
    $note.Left = 20; $note.Top = 445; $note.Width = 390; $note.Height = 48
    $form.Controls.Add($note)

    $form.add_FormClosing({
        param($sender, $eventArgs)
        if (-not $script:Exiting -and $eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $eventArgs.Cancel = $true
            $sender.Hide()
        }
    })
    return $form
}

function Show-WnsSettings {
    if ($null -eq $script:SettingsForm -or $script:SettingsForm.IsDisposed) {
        $script:SettingsForm = New-WnsSettingsForm
    }
    Update-WnsSettingsView
    $script:SettingsForm.Show()
    $script:SettingsForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $script:SettingsForm.Activate()
}

function Exit-WnsApplication {
    if ($script:Exiting) { return }

    $script:Exiting = $true
    try {
        if ($script:State.Status -ne 'EXITING') {
            Set-WnsRuntimeState -Status 'EXITING' -Reason 'Application exit requested; restoring temporary policy.'
        }
        [void](Restore-WnsOwnedPolicy -Reason 'application exit')
        Disable-WnsShutdownGuard
        Disable-WnsPowerRequests
        $script:CoreProtectionActive = $false
    }
    finally {
        if ($null -ne $script:BatteryTimer) { $script:BatteryTimer.Stop() }
        if ($null -ne $script:OpenTimer) { $script:OpenTimer.Stop() }
        if ($null -ne $script:NotifyIcon) { $script:NotifyIcon.Visible = $false }
        if ($null -ne $script:SettingsForm -and -not $script:SettingsForm.IsDisposed) { $script:SettingsForm.Dispose() }
        if ($null -ne $script:HostForm -and -not $script:HostForm.IsDisposed) { $script:HostForm.Dispose() }
        [System.Windows.Forms.Application]::ExitThread()
    }
}

# Single-instance ownership also serializes crash/reboot recovery. A recovery-only
# process never restores policy out from under an already running normal owner.
$mutexCreated = $false
$script:Mutex = New-Object System.Threading.Mutex($true, 'Local\WindowsNoSleep.Singleton', [ref]$mutexCreated)
$openEventName = 'Local\WindowsNoSleep.OpenSettings'

if (-not $mutexCreated) {
    if (-not $RecoveryOnly) {
        try {
            $existingEvent = [System.Threading.EventWaitHandle]::OpenExisting($openEventName)
            [void]$existingEvent.Set()
            $existingEvent.Dispose()
        }
        catch {}
    }
    exit 0
}

if ($RecoveryOnly) {
    try {
        Write-WnsLog -Paths $script:Paths -Message 'Recovery-only startup invoked.'
        [void](Restore-WnsOwnedPolicy -Reason 'RunOnce recovery' -ThrowOnFailure)
        Write-WnsLog -Paths $script:Paths -Message 'Recovery-only startup completed.'
        exit 0
    }
    finally {
        try {
            $script:Mutex.ReleaseMutex()
            $script:Mutex.Dispose()
        }
        catch {}
    }
}

$script:OpenSettingsEvent = New-Object System.Threading.EventWaitHandle(
    $false,
    [System.Threading.EventResetMode]::AutoReset,
    $openEventName
)

try {
    Write-WnsLog -Paths $script:Paths -Message "Starting $($script:AppName) $($script:AppVersion)."

    $recoveryStatus = Get-WnsRecoveryStatus -Paths $script:Paths
    if ($recoveryStatus.Status -eq 'Pending') {
        Set-WnsRuntimeState -Status 'RECOVERING_PREVIOUS_STATE' -Reason 'Restoring temporary policy left by a prior interrupted session.'
        [void](Restore-WnsOwnedPolicy -Reason 'startup recovery' -ThrowOnFailure)
    }
    elseif ($recoveryStatus.Status -eq 'Corrupt') {
        throw "Recovery data is corrupt. Protection will not start because exact restoration cannot be proven: $($recoveryStatus.Error)"
    }
    else {
        Disable-WnsRecoveryRunOnce
    }

    $script:HostForm = New-Object WindowsNoSleep.Interop.ShutdownHostForm
    [void]$script:HostForm.Handle
    $script:HostForm.add_ShutdownBlocked({
        Write-WnsLog -Paths $script:Paths -Level 'WARN' -Message 'Windows requested session shutdown/restart; normal shutdown was blocked by active protection.'
    })

    $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $openMenu = $contextMenu.Items.Add('Open Settings')
    $script:ToggleMenu = $contextMenu.Items.Add('Stop Protection')
    [void]$contextMenu.Items.Add('-')
    $exitMenu = $contextMenu.Items.Add('Exit')

    $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:NotifyIcon.ContextMenuStrip = $contextMenu
    $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
    $script:NotifyIcon.Text = 'Windows No Sleep - Starting'
    $script:NotifyIcon.Visible = $true

    $openMenu.add_Click({ Show-WnsSettings })
    $exitMenu.add_Click({ Exit-WnsApplication })
    $script:ToggleMenu.add_Click({
        if ($script:State.Status -eq 'PROTECTED' -or $script:State.Status -eq 'DEGRADED') {
            Stop-WnsProtection -UserInitiated
        }
        else {
            $script:UserStopped = $false
            Start-WnsProtection
        }
    })

    $script:NotifyIcon.add_MouseClick({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            Show-WnsSettings
        }
    })

    $script:OpenTimer = New-Object System.Windows.Forms.Timer
    $script:OpenTimer.Interval = 400
    $script:OpenTimer.add_Tick({
        if ($script:OpenSettingsEvent.WaitOne(0)) { Show-WnsSettings }
    })
    $script:OpenTimer.Start()

    $script:BatteryTimer = New-Object System.Windows.Forms.Timer
    $script:BatteryTimer.Interval = 5000
    $script:BatteryTimer.add_Tick({
        try {
            $battery = Get-WnsBatterySnapshot
            $threshold = Get-WnsBatteryThreshold

            if (-not $script:UserStopped -and [bool]$script:Settings.KeepComputerAwake) {
                if ($battery.HasBattery -and -not $battery.OnAC -and (
                    (-not [bool]$script:Settings.ProtectOnBattery) -or
                    ($null -ne $battery.Percent -and $battery.Percent -le $threshold)
                )) {
                    if ($script:State.Status -ne 'BATTERY_SAFETY') { Enter-WnsBatterySafety }
                }
                elseif ($script:State.Status -eq 'BATTERY_SAFETY') {
                    $resumeThreshold = [Math]::Min(100, $threshold + 5)
                    if ($battery.OnAC -or ($null -ne $battery.Percent -and $battery.Percent -ge $resumeThreshold)) {
                        Start-WnsProtection -AutomaticResume
                    }
                }
                elseif ($script:CoreProtectionActive -and $battery.HasBattery) {
                    try {
                        Sync-WnsOwnedPolicy
                        if ($script:State.Status -eq 'DEGRADED') {
                            Set-WnsRuntimeState -Status 'PROTECTED' -Reason 'System power request and temporary runtime policy are healthy.'
                        }
                    }
                    catch {
                        if ($script:State.Status -ne 'DEGRADED') {
                            Set-WnsRuntimeState -Status 'DEGRADED' -Reason "System request remains active, but runtime policy sync failed: $($_.Exception.Message)"
                        }
                        else {
                            Write-WnsLog -Paths $script:Paths -Level 'ERROR' -Message "Runtime policy sync retry failed: $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
        catch {
            Write-WnsLog -Paths $script:Paths -Level 'ERROR' -Message "Battery/runtime timer error: $($_.Exception.Message)"
        }

        Update-WnsTrayState
        Update-WnsSettingsView
    })
    $script:BatteryTimer.Start()

    if ([bool]$script:Settings.KeepComputerAwake) {
        Start-WnsProtection
    }
    else {
        Set-WnsRuntimeState -Status 'STOPPED' -Reason 'Protection disabled in settings.'
    }

    Update-WnsTrayState
    [System.Windows.Forms.Application]::Run()
}
catch {
    try { Write-WnsLog -Paths $script:Paths -Level 'ERROR' -Message "Fatal error: $($_.Exception.ToString())" } catch {}
    try {
        [System.Windows.Forms.MessageBox]::Show(
            "Windows No Sleep could not start.`r`n`r`n$($_.Exception.Message)",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {}
}
finally {
    try { [void](Restore-WnsOwnedPolicy -Reason 'final process cleanup') } catch {}
    try { Disable-WnsShutdownGuard } catch {}
    try { Disable-WnsPowerRequests } catch {}
    try {
        if ($null -ne $script:NotifyIcon) {
            $script:NotifyIcon.Visible = $false
            $script:NotifyIcon.Dispose()
        }
    }
    catch {}
    try { if ($null -ne $script:OpenSettingsEvent) { $script:OpenSettingsEvent.Dispose() } } catch {}
    try {
        if ($null -ne $script:Mutex) {
            $script:Mutex.ReleaseMutex()
            $script:Mutex.Dispose()
        }
    }
    catch {}
}
