using System;
using System.Drawing;
using System.Windows.Forms;

namespace WindowsNoSleep
{
    internal sealed class SettingsForm : Form
    {
        private readonly TrayApplicationContext _context;
        private readonly Label _statusLabel;
        private readonly Button _toggleButton;

        internal SettingsForm(TrayApplicationContext context)
        {
            _context = context ?? throw new ArgumentNullException(nameof(context));

            Text = "Windows No Sleep";
            Width = 460;
            Height = 240;
            MinimumSize = new Size(460, 240);
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Icon = LoadApplicationIcon();

            var title = new Label
            {
                Left = 20,
                Top = 20,
                Width = 400,
                Height = 24,
                Font = new Font(Font, FontStyle.Bold),
                Text = "Windows No Sleep"
            };

            _statusLabel = new Label
            {
                Left = 20,
                Top = 58,
                Width = 400,
                Height = 48
            };

            var note = new Label
            {
                Left = 20,
                Top = 108,
                Width = 400,
                Height = 24,
                Text = "Your display may still turn off normally."
            };

            _toggleButton = new Button
            {
                Left = 20,
                Top = 150,
                Width = 145,
                Height = 30
            };
            _toggleButton.Click += delegate
            {
                if (_context.IsProtected)
                {
                    _context.StopProtection();
                }
                else
                {
                    _context.StartProtection();
                }

                RefreshState();
            };

            var closeButton = new Button
            {
                Left = 175,
                Top = 150,
                Width = 110,
                Height = 30,
                Text = "Close"
            };
            closeButton.Click += delegate { Hide(); };

            Controls.Add(title);
            Controls.Add(_statusLabel);
            Controls.Add(note);
            Controls.Add(_toggleButton);
            Controls.Add(closeButton);

            FormClosing += delegate(object sender, FormClosingEventArgs e)
            {
                if (e.CloseReason == CloseReason.UserClosing)
                {
                    e.Cancel = true;
                    Hide();
                }
            };

            RefreshState();
        }

        private static Icon LoadApplicationIcon()
        {
            try
            {
                return Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            }
            catch
            {
                return null;
            }
        }

        internal void RefreshState()
        {
            _statusLabel.Text = _context.StatusText;
            _toggleButton.Text = _context.IsProtected ? "Stop Protection" : "Start Protection";
        }
    }
}
