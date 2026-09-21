using System;
using System.Drawing;
using System.Windows.Forms;

namespace WindowsNoSleep
{
    internal sealed class TrayApplicationContext : ApplicationContext, IDisposable
    {
        private readonly NotifyIcon _notifyIcon;
        private readonly Icon _applicationIcon;
        private readonly ToolStripMenuItem _toggleItem;
        private SettingsForm _settingsForm;
        private PowerRequestLease _powerRequest;
        private bool _disposed;
        private string _lastError;

        internal TrayApplicationContext()
        {
            _applicationIcon = LoadApplicationIcon();

            var menu = new ContextMenuStrip();
            var openItem = new ToolStripMenuItem("Open Settings", null, delegate { ShowSettings(); });
            _toggleItem = new ToolStripMenuItem("Stop Protection", null, delegate { ToggleProtection(); });
            var exitItem = new ToolStripMenuItem("Exit", null, delegate { ExitApplication(); });

            menu.Items.Add(openItem);
            menu.Items.Add(_toggleItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(exitItem);

            _notifyIcon = new NotifyIcon
            {
                ContextMenuStrip = menu,
                Icon = _applicationIcon,
                Text = "Windows No Sleep - Starting",
                Visible = true
            };
            _notifyIcon.MouseClick += OnNotifyIconMouseClick;

            StartProtection();
        }

        internal bool IsProtected
        {
            get { return _powerRequest != null && _powerRequest.IsActive; }
        }

        internal string StatusText
        {
            get
            {
                if (IsProtected)
                {
                    return "Protection active — this computer will stay awake while Windows No Sleep is running.";
                }

                if (!string.IsNullOrWhiteSpace(_lastError))
                {
                    return "Protection degraded — " + _lastError;
                }

                return "Protection stopped — Windows may sleep normally.";
            }
        }

        internal void StartProtection()
        {
            if (IsProtected)
            {
                return;
            }

            try
            {
                _powerRequest = PowerRequestLease.AcquireSystemRequired(
                    "Windows No Sleep is keeping this computer available for its running workloads.");
                _lastError = null;
            }
            catch (Exception ex)
            {
                _lastError = ex.Message;
                if (_powerRequest != null)
                {
                    _powerRequest.Dispose();
                    _powerRequest = null;
                }
            }

            UpdateUiState();
        }

        internal void StopProtection()
        {
            if (_powerRequest != null)
            {
                _powerRequest.Dispose();
                _powerRequest = null;
            }

            _lastError = null;
            UpdateUiState();
        }

        internal void ShowSettings()
        {
            if (_settingsForm == null || _settingsForm.IsDisposed)
            {
                _settingsForm = new SettingsForm(this);
            }

            _settingsForm.RefreshState();
            _settingsForm.Show();
            _settingsForm.WindowState = FormWindowState.Normal;
            _settingsForm.Activate();
            _settingsForm.BringToFront();
        }

        private void ToggleProtection()
        {
            if (IsProtected)
            {
                StopProtection();
            }
            else
            {
                StartProtection();
            }
        }

        private void UpdateUiState()
        {
            if (IsProtected)
            {
                _notifyIcon.Text = "Windows No Sleep - Protected";
                _toggleItem.Text = "Stop Protection";
            }
            else if (!string.IsNullOrWhiteSpace(_lastError))
            {
                _notifyIcon.Text = "Windows No Sleep - Degraded";
                _toggleItem.Text = "Start Protection";
            }
            else
            {
                _notifyIcon.Text = "Windows No Sleep - Stopped";
                _toggleItem.Text = "Start Protection";
            }

            if (_settingsForm != null && !_settingsForm.IsDisposed)
            {
                _settingsForm.RefreshState();
            }
        }

        private static Icon LoadApplicationIcon()
        {
            try
            {
                return Icon.ExtractAssociatedIcon(Application.ExecutablePath)
                    ?? (Icon)SystemIcons.Application.Clone();
            }
            catch
            {
                return (Icon)SystemIcons.Application.Clone();
            }
        }

        private void OnNotifyIconMouseClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                ShowSettings();
            }
        }

        private void ExitApplication()
        {
            StopProtection();
            ExitThread();
        }

        protected override void ExitThreadCore()
        {
            Dispose();
            base.ExitThreadCore();
        }

        public new void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;

            if (_powerRequest != null)
            {
                _powerRequest.Dispose();
                _powerRequest = null;
            }

            if (_settingsForm != null && !_settingsForm.IsDisposed)
            {
                _settingsForm.Dispose();
            }

            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _applicationIcon.Dispose();
        }
    }
}
