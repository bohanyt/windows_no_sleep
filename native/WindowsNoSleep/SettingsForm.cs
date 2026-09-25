using System;
using System.Drawing;
using System.Windows.Forms;

namespace WindowsNoSleep
{
    internal sealed class SettingsForm : Form
    {
        private readonly TrayApplicationContext _context;
        private readonly Label _status, _power, _policy, _desktop;
        private readonly CheckBox _screenSaver, _onBattery, _lid, _timeouts, _shutdown, _startup;
        private readonly NumericUpDown _threshold;
        private readonly Button _toggle, _admin;
        private bool _binding;

        internal SettingsForm(TrayApplicationContext context)
        {
            _context = context;
            Text = "Windows No Sleep"; Icon = context.BrandIcon;
            Font = new Font("Segoe UI", 9F);
            AutoScaleMode = AutoScaleMode.Font;
            AutoSize = true; AutoSizeMode = AutoSizeMode.GrowAndShrink;
            MinimumSize = new Size(580, 0);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; StartPosition = FormStartPosition.CenterScreen;
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 1, Padding = new Padding(18) };
            layout.Controls.Add(new Label { Text = "Windows No Sleep", AutoSize = true, Font = new Font(Font, FontStyle.Bold), Margin = new Padding(0, 0, 0, 12) });
            _status = Paragraph(); _desktop = Paragraph(); _power = Paragraph(); _policy = Paragraph();
            layout.Controls.Add(_status); layout.Controls.Add(_desktop); layout.Controls.Add(_power); layout.Controls.Add(_policy);
            _screenSaver = Option("Prevent screensaver and automatic idle lock");
            _screenSaver.ThreeState = true;
            layout.Controls.Add(_screenSaver);
            layout.Controls.Add(Paragraph("If a local machine inactivity limit is configured, Windows No Sleep requests administrator approval only for that policy change. The main app stays in your signed-in account. Domain/MDM policy may reapply it."));
            _admin = new Button { Text = "Retry administrator protection", AutoSize = true, MinimumSize = new Size(200, 30), Visible = false };
            _admin.Click += delegate { _context.RetryAdministratorIdleLock(); };
            layout.Controls.Add(_admin);
            _onBattery = Option("Keep protecting while on battery");
            _lid = Option("Keep running when the lid is closed");
            _timeouts = Option("Prevent battery sleep / hibernate timeouts");
            _shutdown = Option("Block normal shutdown / restart (best effort)");
            layout.Controls.Add(_onBattery); layout.Controls.Add(_lid); layout.Controls.Add(_timeouts); layout.Controls.Add(_shutdown);
            var batteryRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Margin = new Padding(0, 6, 0, 8) };
            batteryRow.Controls.Add(new Label { Text = "Battery Safety at", AutoSize = true, Margin = new Padding(0, 5, 6, 0) });
            _threshold = new NumericUpDown { Minimum = 15, Maximum = 95, Value = 15, Width = 60 };
            batteryRow.Controls.Add(_threshold);
            batteryRow.Controls.Add(new Label { Text = "% or higher if Windows requires it", AutoSize = true, Margin = new Padding(4, 5, 0, 0) });
            layout.Controls.Add(batteryRow);
            _startup = new CheckBox { Text = "Start with Windows (after I sign in)", AutoSize = true, Margin = new Padding(0, 5, 0, 8) };
            layout.Controls.Add(_startup);
            var diagnostics = new LinkLabel { Text = "Diagnostics and restoration log", AutoSize = true, Margin = new Padding(0, 8, 0, 10) };
            diagnostics.LinkClicked += delegate { _context.ShowDiagnostics(); };
            layout.Controls.Add(diagnostics);
            var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
            _toggle = new Button { Text = "Stop Protection", AutoSize = true, MinimumSize = new Size(145, 32) };
            _toggle.Click += delegate { _context.Toggle(); RefreshState(); };
            var close = new Button { Text = "Close", AutoSize = true, MinimumSize = new Size(100, 32) };
            close.Click += delegate { Hide(); };
            buttons.Controls.Add(_toggle); buttons.Controls.Add(close);
            layout.Controls.Add(buttons);
            layout.Controls.Add(Paragraph("Close hides this window. To quit, right-click the tray icon and choose Exit."));
            Controls.Add(layout);
            _screenSaver.CheckedChanged += SaveProtectionOptions;
            _onBattery.CheckedChanged += SaveProtectionOptions;
            _lid.CheckedChanged += SaveProtectionOptions;
            _timeouts.CheckedChanged += SaveProtectionOptions;
            _shutdown.CheckedChanged += SaveProtectionOptions;
            _threshold.ValueChanged += SaveProtectionOptions;
            _startup.CheckedChanged += delegate
            {
                if (_binding) return;
                try { _context.SetStartup(_startup.Checked); }
                catch (Exception error) { ShowError(error); }
                RefreshState();
            };
            FormClosing += delegate(object sender, FormClosingEventArgs args)
            {
                if (args.CloseReason == CloseReason.UserClosing) { args.Cancel = true; Hide(); }
            };
            RefreshState();
        }
        private static Label Paragraph(string text = "")
        {
            return new Label { Text = text, AutoSize = true, MaximumSize = new Size(520, 0), Margin = new Padding(0, 0, 0, 10) };
        }
        private static CheckBox Option(string text)
        {
            return new CheckBox { Text = text, AutoSize = true, Margin = new Padding(0, 5, 0, 5) };
        }
        internal static CheckState ScreenSaverCheckState(bool requested, bool needsAdministrator)
        {
            if (!requested) return CheckState.Unchecked;
            return needsAdministrator ? CheckState.Indeterminate : CheckState.Checked;
        }
        private void SaveProtectionOptions(object sender, EventArgs args)
        {
            if (_binding) return;
            var options = _context.Controller.Options.Copy();
            options.PreventScreenSaver = _screenSaver.CheckState != CheckState.Unchecked;
            options.ProtectOnBattery = _onBattery.Checked;
            options.LidProtection = _lid.Checked;
            options.DcTimeoutProtection = _timeouts.Checked;
            options.BlockShutdown = _shutdown.Checked;
            options.BatterySafetyPercent = (int)_threshold.Value;
            try { _context.SaveOptions(options); }
            catch (Exception error) { ShowError(error); }
            RefreshState();
        }
        private void ShowError(Exception error)
        {
            MessageBox.Show(this, error.Message, "Windows No Sleep", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        internal void RefreshState()
        {
            _binding = true;
            try
            {
                var core = _context.Controller;
                _status.Text = core.State + "\n" + core.Detail;
                _desktop.Text = "Screensaver / idle lock: " + core.ScreenSaverDetail;
                _power.Text = _context.BatteryText();
                _policy.Text = "Temporary settings: " + core.PolicyDetail
                    + "\nRestart guard: " + (core.GuardActive ? "Active - Windows can override it" : "Off")
                    + (_context.StartupWarning == null ? "" : "\n" + _context.StartupWarning);
                bool screenSaverRequested = core.Options.PreventScreenSaver != false;
                bool needsAdministrator = screenSaverRequested && _context.NeedsAdministratorForIdleLock;
                _screenSaver.CheckState = ScreenSaverCheckState(screenSaverRequested, needsAdministrator);
                _admin.Visible = needsAdministrator;
                _onBattery.Checked = core.Options.ProtectOnBattery;
                _lid.Checked = core.Options.LidProtection;
                _timeouts.Checked = core.Options.DcTimeoutProtection;
                _shutdown.Checked = core.Options.BlockShutdown;
                _threshold.Value = core.Options.BatterySafetyPercent;
                _lid.Enabled = core.Power != null && core.Power.LidPresent;
                _timeouts.Enabled = core.Power != null && core.Power.HasBattery;
                try { _startup.Checked = _context.Startup.Enabled; _startup.Enabled = true; }
                catch { _startup.Checked = false; _startup.Enabled = false; }
                _toggle.Text = core.Wanted ? "Stop Protection" : "Start Protection";
            }
            finally { _binding = false; }
        }
    }
}
