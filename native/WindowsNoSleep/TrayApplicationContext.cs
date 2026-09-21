using System;
using System.Collections.Generic;
using System.Drawing;
using System.Diagnostics;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace WindowsNoSleep
{
    internal sealed class TrayApplicationContext : ApplicationContext
    {
        private readonly RuntimeStorage _storage;
        private readonly ShutdownWindow _lifecycle;
        private readonly ApplicationRecoveryRegistration _recovery;
        private readonly NamedOwnership _policyOwnership;
        private readonly ScreenSaverProtection _screenSaver;
        private readonly NotifyIcon _notifyIcon;
        private readonly ContextMenuStrip _menu;
        private readonly ToolStripMenuItem _toggle;
        private readonly Timer _timer;
        private readonly Icon _brand;
        private readonly Dictionary<ProtectionState, Icon> _icons = new Dictionary<ProtectionState, Icon>();
        private SettingsForm _settings;
        private bool _disposed, _sessionEvents;
        private int _ticks;
        internal ProtectionController Controller { get; private set; }
        internal StartupManager Startup { get; private set; }
        internal string StartupWarning { get; private set; }
        internal Icon BrandIcon { get { return _brand; } }

        internal TrayApplicationContext(string directory)
        {
            _storage = new RuntimeStorage(directory);
            string warning;
            AppOptions options = _storage.LoadOptions(out warning);
            StartupWarning = warning;
            if (warning != null) options.PreventScreenSaver = false; // Corrupt settings: no new session mutation.
            string policyError = null;
            try
            {
                _policyOwnership = new NamedOwnership(@"Global\WindowsNoSleep.Native.PowerPolicy.v1");
                if (!_policyOwnership.Acquired) policyError = "Another session owns the power-policy transaction.";
            }
            catch (Exception error) { policyError = "Power-policy ownership unavailable: " + error.Message; }
            string machine = null;
            try { machine = RuntimeStorage.MachineId; }
            catch (Exception error) { policyError = error.Message; }
            var platform = new WindowsPowerPlatform();
            var store = new NativeJournalStore(directory, machine, RuntimeStorage.UserId);
            var transaction = new PolicyTransaction(platform, store, _storage.Log);
            var desktopPlatform = new WindowsScreenSaverPlatform();
            _screenSaver = new ScreenSaverProtection(desktopPlatform, new ScreenSaverJournalStore(directory), _storage.Log,
                desktopPlatform, new MachineInactivityJournalStore(directory, machine, RuntimeStorage.UserId));
            _lifecycle = new ShutdownWindow(_storage.Log);
            Controller = new ProtectionController(options, platform, transaction, _lifecycle,
                delegate { return PowerRequestLease.AcquireSystemRequired("Windows No Sleep is keeping computer workloads active while allowing the display to turn off."); }, _storage.Log, _screenSaver);
            _recovery = new ApplicationRecoveryRegistration(Controller.RecoverForCrash);
            Controller.PolicyRecoveryReady = policyError == null && _recovery.Ready;
            Controller.PolicyRecoveryError = policyError ?? _recovery.Error;
            _screenSaver.RecoveryReady = _recovery.Ready;
            _screenSaver.RecoveryError = _recovery.Error;
            Startup = new StartupManager(Application.ExecutablePath);
            _lifecycle.CanBlock = Controller.MayBlockShutdown;
            _lifecycle.SessionEnded = delegate { Controller.Stop(); ExitThread(); };
            _lifecycle.PowerChanged = QueuePowerEvent;
            try { _brand = Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? (Icon)SystemIcons.Application.Clone(); }
            catch { _brand = (Icon)SystemIcons.Application.Clone(); }
            _icons[ProtectionState.Protected] = Badge(Color.ForestGreen, "+");
            _icons[ProtectionState.Stopped] = Badge(Color.DimGray, "-");
            _icons[ProtectionState.BatterySafety] = Badge(Color.DarkOrange, "B");
            _icons[ProtectionState.Degraded] = Badge(Color.Firebrick, "!");
            _icons[ProtectionState.Suspended] = Badge(Color.DimGray, "-");
            _icons[ProtectionState.Starting] = Badge(Color.DimGray, ".");
            _menu = new ContextMenuStrip();
            _menu.Items.Add("Open Settings", null, delegate { ShowSettings(); });
            _toggle = new ToolStripMenuItem("Stop Protection", null, delegate { Toggle(); });
            _menu.Items.Add(_toggle);
            _menu.Items.Add("Diagnostics", null, delegate { ShowDiagnostics(); });
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add("Exit", null, delegate { ExitApplication(); });
            _notifyIcon = new NotifyIcon { ContextMenuStrip = _menu, Icon = _brand, Text = "Windows No Sleep - Starting", Visible = true };
            _notifyIcon.MouseClick += delegate(object sender, MouseEventArgs args) { if (args.Button == MouseButtons.Left) ShowSettings(); };
            _timer = new Timer { Interval = 2000 };
            _timer.Tick += delegate
            {
                Controller.Poll(); RefreshUi();
                if (++_ticks % 15 == 0) _storage.Log("HEARTBEAT state=" + Controller.State + " awake=" + Controller.IsAwake
                    + " screensaverSuppressed=" + _screenSaver.Active + " battery=" + BatteryText());
            };
            try { SystemEvents.SessionSwitch += OnSessionSwitch; _sessionEvents = true; }
            catch (Exception error) { _storage.Log("SESSION_OBSERVER_UNAVAILABLE " + error.Message); }
        }
        internal void Initialize()
        {
            _storage.Log("START version=" + Application.ProductVersion + " build=" + BuildId());
            if (StartupWarning != null) _storage.Log(StartupWarning);
            Controller.Start();
            RefreshUi(); _timer.Start();
            if ((Controller.RecoveryPending && !Controller.IsAwake) || Controller.ScreenSaverWarning != null) ShowSettings();
        }
        private void OnSessionSwitch(object sender, SessionSwitchEventArgs args)
        {
            if (_disposed || !_lifecycle.IsHandleCreated) return;
            try
            {
                _lifecycle.BeginInvoke((Action)delegate
                {
                    if (_disposed) return;
                    if (args.Reason == SessionSwitchReason.SessionLock) _screenSaver.ObserveSessionLock();
                    if (args.Reason == SessionSwitchReason.SessionUnlock) _storage.Log("SESSION_UNLOCK_OBSERVED");
                    Controller.Poll(); RefreshUi();
                });
            }
            catch (InvalidOperationException) { }
        }
        private void QueuePowerEvent(int code)
        {
            if (_disposed || !_lifecycle.IsHandleCreated) return;
            try
            {
                _lifecycle.BeginInvoke((Action)delegate
                {
                    if (_disposed) return;
                    if (code == 4) Controller.Suspend();
                    else if (code == 7 || code == 18) Controller.Resume();
                    else Controller.Poll();
                    RefreshUi();
                });
            }
            catch (InvalidOperationException) { }
        }
        internal void Toggle()
        {
            if (Controller.Wanted) Controller.Stop(); else Controller.Start();
            RefreshUi();
        }
        internal void SaveOptions(AppOptions options)
        {
            Controller.ChangeOptions(options, _storage.SaveOptions);
            StartupWarning = null;
            RefreshUi();
        }
        internal void SetStartup(bool enabled)
        {
            Startup.SetEnabled(enabled);
            _storage.Log("AUTOSTART enabled=" + enabled);
        }
        internal bool NeedsAdministratorForIdleLock
        {
            get
            {
                string warning = Controller.ScreenSaverWarning;
                return warning != null && warning.IndexOf("administrator", StringComparison.OrdinalIgnoreCase) >= 0;
            }
        }
        internal void RestartAsAdministrator()
        {
            Controller.Stop();
            if (Controller.RecoveryPending)
            {
                MessageBox.Show("Original settings still need recovery. Run the current executable as administrator manually so Windows No Sleep can restore them before continuing.",
                    "Windows No Sleep", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            try
            {
                Process.Start(new ProcessStartInfo(Application.ExecutablePath)
                {
                    UseShellExecute = true,
                    Verb = "runas",
                    WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory
                });
                ExitThread();
            }
            catch (Win32Exception error)
            {
                if ((error.NativeErrorCode & 0xffff) != 1223)
                    MessageBox.Show(error.Message, "Windows No Sleep", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
        internal void ShowSettings()
        {
            if (_disposed) return;
            if (_settings == null || _settings.IsDisposed) _settings = new SettingsForm(this);
            _settings.RefreshState(); _settings.Show(); _settings.WindowState = FormWindowState.Normal;
            _settings.Activate();
        }
        private void RefreshUi()
        {
            if (_disposed) return;
            _notifyIcon.Icon = _icons[Controller.State];
            _notifyIcon.Text = "Windows No Sleep - " + Controller.State;
            _toggle.Text = Controller.Wanted ? "Stop Protection" : "Start Protection";
            if (_settings != null && !_settings.IsDisposed) _settings.RefreshState();
        }
        internal string BatteryText()
        {
            PowerSnapshot power = Controller.Power;
            if (power == null || !power.ReadSucceeded) return "Power status unavailable (safety pause)";
            if (!power.HasBattery) return "No battery";
            return (power.OnAc == true ? "Plugged in" : power.OnAc == false ? "On battery" : "Power source unknown")
                + " | " + (power.Percent.HasValue ? power.Percent + "%" : "charge unknown")
                + " | Safety threshold " + Controller.EffectiveThreshold + "%";
        }
        private static string BuildId()
        {
            try { return File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "BUILD_SHA.txt")).Trim(); }
            catch { return "local build"; }
        }
        internal void ShowDiagnostics()
        {
            var form = new Form { Text = "Windows No Sleep - Diagnostics", Icon = _brand, Width = 800, Height = 550, StartPosition = FormStartPosition.CenterScreen };
            var text = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false, Dock = DockStyle.Fill };
            text.Text = "Version: " + Application.ProductVersion + "\r\nBuild: " + BuildId() + "\r\nState: " + Controller.State
                + "\r\n" + Controller.Detail + "\r\n" + BatteryText() + "\r\nPolicy: " + Controller.PolicyDetail
                + "\r\nScreensaver: " + Controller.ScreenSaverDetail + "\r\nIdle-lock limitation: " + (Controller.ScreenSaverWarning ?? "none detected (not an exhaustive policy inventory)")
                + "\r\nSession lock observation registered: " + _sessionEvents
                + "\r\nRecovery pending (includes active restore snapshots): " + Controller.RecoveryPending + "\r\nARR registered: " + _recovery.Ready
                + "\r\nData: " + _storage.DirectoryPath
                + "\r\nLimits: manual Win+L, Dynamic Lock/presence sensing, enterprise policy, forced shutdown and thermal/critical-battery safety remain authoritative."
                + "\r\nScreenSaverIsSecure/passwords are NOT disabled; only ordinary screensaver activation is suppressed."
                + "\r\nPower loss/force-kill recovery happens on next launch; ARR is best effort.\r\n\r\n" + _storage.ReadLog();
            form.Controls.Add(text);
            form.Show();
        }
        private Icon Badge(Color color, string symbol)
        {
            using (var bitmap = new Bitmap(32, 32))
            using (var graphics = Graphics.FromImage(bitmap))
            using (var brush = new SolidBrush(color))
            using (var font = new Font(FontFamily.GenericSansSerif, 11, FontStyle.Bold, GraphicsUnit.Pixel))
            {
                graphics.DrawIcon(_brand, new Rectangle(0, 0, 32, 32));
                graphics.FillEllipse(brush, 17, 17, 15, 15);
                graphics.DrawString(symbol, font, Brushes.White, 20, 17);
                IntPtr handle = bitmap.GetHicon();
                try { using (var icon = Icon.FromHandle(handle)) return (Icon)icon.Clone(); }
                finally { DestroyIcon(handle); }
            }
        }
        private void ExitApplication()
        {
            Controller.Stop();
            if (Controller.RecoveryPending)
                MessageBox.Show("Some original Windows settings could not be restored. Recovery records are preserved; the next launch will retry before applying new settings.\n\n" + Controller.PolicyDetail + "\n" + Controller.ScreenSaverDetail,
                    "Windows No Sleep - recovery pending", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            ExitThread();
        }
        internal bool RecoverForCrash(Action pulse) { return Controller.RecoverForCrash(pulse); }
        protected override void Dispose(bool disposing)
        {
            if (disposing && !_disposed)
            {
                _disposed = true;
                if (_sessionEvents) SystemEvents.SessionSwitch -= OnSessionSwitch;
                _timer.Stop(); _timer.Dispose();
                Controller.Stop();
                _notifyIcon.Visible = false; _notifyIcon.Dispose();
                if (_settings != null) _settings.Dispose();
                _menu.Dispose(); _lifecycle.Dispose(); _recovery.Dispose();
                foreach (var icon in _icons.Values) icon.Dispose();
                _brand.Dispose();
                if (_policyOwnership != null) _policyOwnership.Dispose();
                _storage.Log("EXIT cleanup completed; recoveryPending=" + Controller.RecoveryPending);
            }
            base.Dispose(disposing);
        }
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DestroyIcon(IntPtr icon);
    }
}
