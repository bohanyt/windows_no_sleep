#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'Windows No Sleep'
$script:AppVersion = '0.1.0-dev'
$script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CoreModule = Join-Path $script:ScriptRoot 'src\WindowsNoSleep.Core.psm1'

Import-Module $script:CoreModule -Force
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('WindowsNoSleep.Interop.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace WindowsNoSleep.Interop
{
    public enum PowerRequestType
    {
        DisplayRequired = 0,
        SystemRequired = 1,
        AwayModeRequired = 2,
        ExecutionRequired = 3
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct ReasonContext
    {
        public UInt32 Version;
        public UInt32 Flags;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string SimpleReasonString;
    }

    public static class NativeMethods
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr PowerCreateRequest(ref ReasonContext Context);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PowerSetRequest(IntPtr PowerRequest, PowerRequestType RequestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PowerClearRequest(IntPtr PowerRequest, PowerRequestType RequestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShutdownBlockReasonCreate(IntPtr hWnd, string pwszReason);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShutdownBlockReasonDestroy(IntPtr hWnd);
    }

    public sealed class ShutdownHostForm : Form
    {
        public bool BlockShutdown { get; set; }
        public event EventHandler ShutdownBlocked;

        public ShutdownHostForm()
        {
            BlockShutdown = false;
            ShowInTaskbar = false;
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            Opacity = 0.0;
            Width = 1;
            Height = 1;
            StartPosition = FormStartPosition.Manual;
            Location = new Point(-32000, -32000);
            Text = "Windows No Sleep Host";
        }

        protected override void SetVisibleCore(bool value)
        {
            base.SetVisibleCore(false);
        }

        protected override void WndProc(ref Message m)
        {
            const int WM_QUERYENDSESSION = 0x0011;

            if (m.Msg == WM_QUERYENDSESSION && BlockShutdown)
            {
                EventHandler handler = ShutdownBlocked;
                if (handler != null)
                {
                    handler(this, EventArgs.Empty);
                }

                m.Result = IntPtr.Zero;
                return;
            }

            base.WndProc(ref m);
        }
    }
}
'@
}

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
$script:UserStopped = $false
$script:Exiting = $false
$script:SettingsForm = $null
$script:NotifyIcon = $null
$script:HostForm = $null
$script:BatteryTimer = $null
$script:OpenTimer = $null

function Get-WnsLastWin32ErrorText {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $message = (New-Object ComponentModel.Win32Exception($code)).Message
    return "Win32 error $code`: $message"
}

function Get-WnsBatterySnapshot {
    $status = [System.Windows.Forms.SystemInformation]::PowerStatus
    $noSystemBattery = (($status.BatteryChargeStatus -band [System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery) -ne 0)
    $percent = $null

    if (-not $noSystemBattery -and $status.BatteryLifePercent -ge 0) {
        $percent = [int][Math]::Round(([double]$status.BatteryLifePercent) * 100.0)
        $percent = [Math]::Min(100, [Math]::Max(0, $percent))
    }

    return [pscustomobject]@{
        HasBattery = (-not $noSystemBattery)
        OnAC       = ($status.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)
        Percent    = $percent
        RawStatus  = [string]$status.BatteryChargeStatus
    }
}

function Get-WnsBatteryThreshold {
    # Reading the Windows/OEM critical threshold is added in the transactional
    # power-policy phase. Until then, use the owner-approved base threshold.
    return Get-WnsEffectiveBatterySafetyThreshold -BasePercent $script:Settings.BatterySafetyPercent
}

function Set-WnsRuntimeState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    $script:State = Set-WnsState -State $script:State -Status $Status -Reason $Reason
    Write-WnsLog -Paths $script:Paths -Message ("State -> {0}: {1}" -f $Status, $Reason)
    Update-WnsTrayState
    Update-WnsSettingsView
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

    if ($script:Settings.KeepDisplayOn -and -not $script:DisplayRequestSet) {
        if (-not [WindowsNoSleep.Interop.NativeMethods]::PowerSetRequest(
            $script:PowerHandle,
            [WindowsNoSleep.Interop.PowerRequestType]::DisplayRequired
        )) {
            throw "PowerSetRequest(DisplayRequired) failed. $(Get-WnsLastWin32ErrorText)"
        }
        $script:DisplayRequestSet = $true
    }
    elseif (-not $script:Settings.KeepDisplayOn -and $script:DisplayRequestSet) {
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
        [void][WindowsNoSleep.Interop.NativeMethods]::PowerClearRequest(
            $script:PowerHandle,
            [WindowsNoSleep.Interop.PowerRequestType]::DisplayRequired
        )
        $script:DisplayRequestSet = $false
    }

    if ($script:SystemRequestSet) {
        [void][WindowsNoSleep.Interop.NativeMethods]::PowerClearRequest(
            $script:PowerHandle,
            [WindowsNoSleep.Interop.PowerRequestType]::SystemRequired
        )
        $script:SystemRequestSet = $false
    }

    [void][WindowsNoSleep.Interop.NativeMethods]::CloseHandle($script:PowerHandle)
    $script:PowerHandle = [IntPtr]::Zero
}

function Enable-WnsShutdownGuard {
    if (-not $script:Settings.BlockRestart) {
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

    if (-not $script:Settings.ProtectOnBattery) {
        return $true
    }

    if ($null -eq $battery.Percent) {
        return $false
    }

    return ($battery.Percent -le (Get-WnsBatteryThreshold))
}

function Enter-WnsBatterySafety {
    $battery = Get-WnsBatterySnapshot
    Disable-WnsShutdownGuard
    Disable-WnsPowerRequests

    # The transactional lid/sleep restoration provider is intentionally not
    # wired until the dedicated Windows integration phase. When it is added,
    # restoration must happen here before BATTERY_SAFETY is announced.
    $reason = if (-not $script:Settings.ProtectOnBattery) {
        'Battery protection is disabled by settings.'
    }
    elseif ($null -ne $battery.Percent) {
        "Battery is $($battery.Percent)% (safety threshold $(Get-WnsBatteryThreshold)%)."
    }
    else {
        'Battery safety requested.'
    }

    if ($script:State.Status -ne 'BATTERY_SAFETY') {
        Set-WnsRuntimeState -Status 'BATTERY_SAFETY' -Reason $reason
    }
}

function Start-WnsProtection {
    param(
        [switch]$AutomaticResume
    )

    if (-not $script:Settings.KeepComputerAwake) {
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

        if (-not $AutomaticResume) {
            $script:UserStopped = $false
        }

        if ($script:State.Status -ne 'PROTECTED') {
            Set-WnsRuntimeState -Status 'PROTECTED' -Reason 'System power request is active.'
        }
    }
    catch {
        Disable-WnsShutdownGuard
        Disable-WnsPowerRequests
        Set-WnsRuntimeState -Status 'DEGRADED' -Reason $_.Exception.Message
    }
}

function Stop-WnsProtection {
    param(
        [string]$Reason = 'Protection stopped by operator.',
        [switch]$UserInitiated
    )

    Disable-WnsShutdownGuard
    Disable-WnsPowerRequests

    if ($UserInitiated) {
        $script:UserStopped = $true
    }

    if ($script:State.Status -ne 'STOPPED' -and $script:State.Status -ne 'EXITING') {
        Set-WnsRuntimeState -Status 'STOPPED' -Reason $Reason
    }
}

function Set-WnsAutostart {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $valueName = 'WindowsNoSleep'

    if ($Enabled) {
        $scriptPath = $MyInvocation.ScriptName
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            $scriptPath = Join-Path $script:ScriptRoot 'WindowsNoSleep.ps1'
        }
        $command = 'powershell.exe -NoProfile -STA -WindowStyle Hidden -File "{0}"' -f $scriptPath
        New-Item -Path $runKey -Force | Out-Null
        Set-ItemProperty -Path $runKey -Name $valueName -Value $command -Type String
    }
    else {
        Remove-ItemProperty -Path $runKey -Name $valueName -ErrorAction SilentlyContinue
    }
}

function Update-WnsTrayState {
    if ($null -eq $script:NotifyIcon) {
        return
    }

    $battery = Get-WnsBatterySnapshot
    $powerText = if ($battery.OnAC) { 'AC' } elseif ($battery.HasBattery) { 'Battery' } else { 'Unknown power' }

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

    if ($text.Length -gt 63) {
        $text = $text.Substring(0, 63)
    }
    $script:NotifyIcon.Text = $text
}

function Update-WnsSettingsView {
    if ($null -eq $script:SettingsForm -or $script:SettingsForm.IsDisposed) {
        return
    }

    $statusLabel = $script:SettingsForm.Controls['StatusLabel']
    $detailLabel = $script:SettingsForm.Controls['DetailLabel']
    $batteryLabel = $script:SettingsForm.Controls['BatteryLabel']
    $startStopButton = $script:SettingsForm.Controls['StartStopButton']

    if ($null -ne $statusLabel) {
        $statusLabel.Text = "Status: $($script:State.Status)"
    }
    if ($null -ne $detailLabel) {
        $detailLabel.Text = $script:State.Reason
    }

    $battery = Get-WnsBatterySnapshot
    if ($null -ne $batteryLabel) {
        if ($battery.HasBattery -and $null -ne $battery.Percent) {
            $source = if ($battery.OnAC) { 'AC' } else { 'Battery' }
            $batteryLabel.Text = "Power: $source | Battery: $($battery.Percent)% | Safety: $(Get-WnsBatteryThreshold)%"
        }
        else {
            $batteryLabel.Text = 'Power: no system battery detected'
        }
    }

    if ($null -ne $startStopButton) {
        $startStopButton.Text = if ($script:State.Status -eq 'PROTECTED' -or $script:State.Status -eq 'DEGRADED') {
            'Stop Protection'
        }
        else {
            'Start Protection'
        }
    }
}

function Save-WnsSettingsFromForm {
    if ($null -eq $script:SettingsForm) {
        return
    }

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

    if ($script:Settings.KeepComputerAwake) {
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
    $form.Text = "Windows No Sleep $($script:AppVersion)"
    $form.Width = 430
    $form.Height = 480
    $form.MinimumSize = New-Object System.Drawing.Size(430, 480)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $true

    $status = New-Object System.Windows.Forms.Label
    $status.Name = 'StatusLabel'
    $status.Left = 20
    $status.Top = 20
    $status.Width = 375
    $status.Height = 25
    $status.Font = New-Object System.Drawing.Font($status.Font, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($status)

    $detail = New-Object System.Windows.Forms.Label
    $detail.Name = 'DetailLabel'
    $detail.Left = 20
    $detail.Top = 48
    $detail.Width = 375
    $detail.Height = 42
    $form.Controls.Add($detail)

    $battery = New-Object System.Windows.Forms.Label
    $battery.Name = 'BatteryLabel'
    $battery.Left = 20
    $battery.Top = 90
    $battery.Width = 375
    $battery.Height = 22
    $form.Controls.Add($battery)

    $keepAwake = New-Object System.Windows.Forms.CheckBox
    $keepAwake.Name = 'KeepComputerAwake'
    $keepAwake.Text = 'Keep computer awake'
    $keepAwake.Left = 20
    $keepAwake.Top = 125
    $keepAwake.Width = 350
    $keepAwake.Checked = [bool]$script:Settings.KeepComputerAwake
    $form.Controls.Add($keepAwake)

    $batteryProtection = New-Object System.Windows.Forms.CheckBox
    $batteryProtection.Name = 'ProtectOnBattery'
    $batteryProtection.Text = 'Protect on battery'
    $batteryProtection.Left = 20
    $batteryProtection.Top = 155
    $batteryProtection.Width = 350
    $batteryProtection.Checked = [bool]$script:Settings.ProtectOnBattery
    $form.Controls.Add($batteryProtection)

    $lid = New-Object System.Windows.Forms.CheckBox
    $lid.Name = 'LidProtection'
    $lid.Text = 'Keep running with lid closed (integration phase pending)'
    $lid.Left = 20
    $lid.Top = 185
    $lid.Width = 370
    $lid.Checked = [bool]$script:Settings.LidProtection
    $lid.Enabled = $false
    $form.Controls.Add($lid)

    $restart = New-Object System.Windows.Forms.CheckBox
    $restart.Name = 'BlockRestart'
    $restart.Text = 'Block normal automatic restart/shutdown'
    $restart.Left = 20
    $restart.Top = 215
    $restart.Width = 360
    $restart.Checked = [bool]$script:Settings.BlockRestart
    $form.Controls.Add($restart)

    $display = New-Object System.Windows.Forms.CheckBox
    $display.Name = 'KeepDisplayOn'
    $display.Text = 'Keep display on (normally leave OFF)'
    $display.Left = 20
    $display.Top = 245
    $display.Width = 350
    $display.Checked = [bool]$script:Settings.KeepDisplayOn
    $form.Controls.Add($display)

    $autostart = New-Object System.Windows.Forms.CheckBox
    $autostart.Name = 'StartWithWindows'
    $autostart.Text = 'Start with Windows'
    $autostart.Left = 20
    $autostart.Top = 275
    $autostart.Width = 350
    $autostart.Checked = [bool]$script:Settings.StartWithWindows
    $form.Controls.Add($autostart)

    $thresholdLabel = New-Object System.Windows.Forms.Label
    $thresholdLabel.Text = 'Battery Safety threshold:'
    $thresholdLabel.Left = 20
    $thresholdLabel.Top = 313
    $thresholdLabel.Width = 190
    $form.Controls.Add($thresholdLabel)

    $threshold = New-Object System.Windows.Forms.NumericUpDown
    $threshold.Name = 'BatterySafetyPercent'
    $threshold.Left = 215
    $threshold.Top = 310
    $threshold.Width = 65
    $threshold.Minimum = 5
    $threshold.Maximum = 50
    $threshold.Value = [decimal]$script:Settings.BatterySafetyPercent
    $form.Controls.Add($threshold)

    $percentLabel = New-Object System.Windows.Forms.Label
    $percentLabel.Text = '%'
    $percentLabel.Left = 285
    $percentLabel.Top = 313
    $percentLabel.Width = 30
    $form.Controls.Add($percentLabel)

    $save = New-Object System.Windows.Forms.Button
    $save.Text = 'Apply Settings'
    $save.Left = 20
    $save.Top = 355
    $save.Width = 120
    $save.Height = 30
    $save.add_Click({ Save-WnsSettingsFromForm })
    $form.Controls.Add($save)

    $startStop = New-Object System.Windows.Forms.Button
    $startStop.Name = 'StartStopButton'
    $startStop.Left = 150
    $startStop.Top = 355
    $startStop.Width = 125
    $startStop.Height = 30
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
    $exit.Text = 'Exit'
    $exit.Left = 285
    $exit.Top = 355
    $exit.Width = 105
    $exit.Height = 30
    $exit.add_Click({ Exit-WnsApplication })
    $form.Controls.Add($exit)

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Display may turn off by default. Lid/sleep-policy transaction is not active in this dev phase.'
    $note.Left = 20
    $note.Top = 400
    $note.Width = 370
    $note.Height = 40
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
    if ($script:Exiting) {
        return
    }

    $script:Exiting = $true
    try {
        if ($script:State.Status -ne 'EXITING') {
            $script:State = Set-WnsState -State $script:State -Status 'EXITING' -Reason 'Application exit requested.'
        }
        Write-WnsLog -Paths $script:Paths -Message 'Application exiting; releasing owned requests.'
        Disable-WnsShutdownGuard
        Disable-WnsPowerRequests
    }
    finally {
        if ($null -ne $script:BatteryTimer) {
            $script:BatteryTimer.Stop()
        }
        if ($null -ne $script:OpenTimer) {
            $script:OpenTimer.Stop()
        }
        if ($null -ne $script:NotifyIcon) {
            $script:NotifyIcon.Visible = $false
        }
        if ($null -ne $script:SettingsForm -and -not $script:SettingsForm.IsDisposed) {
            $script:SettingsForm.Dispose()
        }
        if ($null -ne $script:HostForm -and -not $script:HostForm.IsDisposed) {
            $script:HostForm.Dispose()
        }
        [System.Windows.Forms.Application]::ExitThread()
    }
}

# Single-instance ownership. A second launch signals the existing process to open Settings.
$mutexCreated = $false
$script:Mutex = New-Object System.Threading.Mutex($true, 'Local\WindowsNoSleep.Singleton', [ref]$mutexCreated)
$openEventName = 'Local\WindowsNoSleep.OpenSettings'

if (-not $mutexCreated) {
    try {
        $existingEvent = [System.Threading.EventWaitHandle]::OpenExisting($openEventName)
        [void]$existingEvent.Set()
        $existingEvent.Dispose()
    }
    catch {
        # Existing instance may be starting or stopping. Do not spawn a competing owner.
    }
    exit 0
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
        Write-WnsLog -Paths $script:Paths -Level 'WARN' -Message 'A pending recovery snapshot exists. No new power-policy mutation is implemented in this phase.'
    }
    elseif ($recoveryStatus.Status -eq 'Corrupt') {
        Write-WnsLog -Paths $script:Paths -Level 'ERROR' -Message "Recovery snapshot is corrupt: $($recoveryStatus.Error)"
    }

    $script:HostForm = New-Object WindowsNoSleep.Interop.ShutdownHostForm
    [void]$script:HostForm.Handle
    $script:HostForm.add_ShutdownBlocked({
        Write-WnsLog -Paths $script:Paths -Level 'WARN' -Message 'Windows requested session shutdown/restart; normal shutdown was blocked by active protection.'
    })

    $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $openMenu = $contextMenu.Items.Add('Open Settings')
    $toggleMenu = $contextMenu.Items.Add('Stop Protection')
    [void]$contextMenu.Items.Add('-')
    $exitMenu = $contextMenu.Items.Add('Exit')

    $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:NotifyIcon.ContextMenuStrip = $contextMenu
    $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
    $script:NotifyIcon.Text = 'Windows No Sleep - Starting'
    $script:NotifyIcon.Visible = $true

    $openMenu.add_Click({ Show-WnsSettings })
    $exitMenu.add_Click({ Exit-WnsApplication })
    $toggleMenu.add_Click({
        if ($script:State.Status -eq 'PROTECTED' -or $script:State.Status -eq 'DEGRADED') {
            Stop-WnsProtection -UserInitiated
            $toggleMenu.Text = 'Start Protection'
        }
        else {
            $script:UserStopped = $false
            Start-WnsProtection
            $toggleMenu.Text = 'Stop Protection'
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
        if ($script:OpenSettingsEvent.WaitOne(0)) {
            Show-WnsSettings
        }
    })
    $script:OpenTimer.Start()

    $script:BatteryTimer = New-Object System.Windows.Forms.Timer
    $script:BatteryTimer.Interval = 5000
    $script:BatteryTimer.add_Tick({
        $battery = Get-WnsBatterySnapshot
        $threshold = Get-WnsBatteryThreshold

        if ($battery.HasBattery -and -not $battery.OnAC) {
            if ((-not $script:Settings.ProtectOnBattery) -or ($null -ne $battery.Percent -and $battery.Percent -le $threshold)) {
                if ($script:State.Status -ne 'BATTERY_SAFETY') {
                    Enter-WnsBatterySafety
                }
            }
            elseif ($script:State.Status -eq 'BATTERY_SAFETY' -and -not $script:UserStopped) {
                $resumeThreshold = [Math]::Min(100, $threshold + 5)
                if ($null -ne $battery.Percent -and $battery.Percent -ge $resumeThreshold) {
                    Start-WnsProtection -AutomaticResume
                }
            }
        }
        elseif ($battery.OnAC -and $script:State.Status -eq 'BATTERY_SAFETY' -and -not $script:UserStopped) {
            Start-WnsProtection -AutomaticResume
        }

        Update-WnsTrayState
        Update-WnsSettingsView
    })
    $script:BatteryTimer.Start()

    if ($script:Settings.KeepComputerAwake) {
        Start-WnsProtection
    }
    else {
        Set-WnsRuntimeState -Status 'STOPPED' -Reason 'Protection disabled in settings.'
    }

    Update-WnsTrayState
    [System.Windows.Forms.Application]::Run()
}
catch {
    try {
        Write-WnsLog -Paths $script:Paths -Level 'ERROR' -Message "Fatal error: $($_.Exception.ToString())"
    }
    catch {
    }

    try {
        [System.Windows.Forms.MessageBox]::Show(
            "Windows No Sleep could not start.`r`n`r`n$($_.Exception.Message)",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
    }
}
finally {
    try { Disable-WnsShutdownGuard } catch {}
    try { Disable-WnsPowerRequests } catch {}
    try {
        if ($null -ne $script:NotifyIcon) {
            $script:NotifyIcon.Visible = $false
            $script:NotifyIcon.Dispose()
        }
    }
    catch {}
    try {
        if ($null -ne $script:OpenSettingsEvent) {
            $script:OpenSettingsEvent.Dispose()
        }
    }
    catch {}
    try {
        if ($null -ne $script:Mutex) {
            $script:Mutex.ReleaseMutex()
            $script:Mutex.Dispose()
        }
    }
    catch {}
}
