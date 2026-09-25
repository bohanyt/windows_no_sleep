using System;
using System.Drawing;
using System.Windows.Forms;

namespace WindowsNoSleep
{
    internal sealed class AlreadyRunningForm : Form
    {
        private const int InitialSeconds = 5;

        private readonly Label _countdownLabel;
        private readonly Timer _timer;
        private int _secondsRemaining = InitialSeconds;

        internal AlreadyRunningForm()
        {
            Text = "Windows No Sleep";
            Width = 430;
            Height = 205;
            MinimumSize = new Size(430, 205);
            MaximumSize = new Size(430, 205);
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = true;
            TopMost = true;
            Icon = LoadApplicationIcon();

            var title = new Label
            {
                Left = 20,
                Top = 20,
                Width = 380,
                Height = 24,
                Font = new Font(Font, FontStyle.Bold),
                Text = "Windows No Sleep is already running"
            };

            var message = new Label
            {
                Left = 20,
                Top = 54,
                Width = 380,
                Height = 42,
                Text = "You can close this message. Windows No Sleep will keep running in the system tray."
            };

            _countdownLabel = new Label
            {
                Left = 20,
                Top = 105,
                Width = 250,
                Height = 24
            };

            var closeButton = new Button
            {
                Left = 300,
                Top = 102,
                Width = 100,
                Height = 30,
                Text = "Close"
            };
            closeButton.Click += delegate { Close(); };

            Controls.Add(title);
            Controls.Add(message);
            Controls.Add(_countdownLabel);
            Controls.Add(closeButton);

            _timer = new Timer
            {
                Interval = 1000
            };
            _timer.Tick += OnTimerTick;

            Shown += delegate
            {
                UpdateCountdownText();
                _timer.Start();
            };

            FormClosed += delegate
            {
                _timer.Stop();
                _timer.Dispose();
            };
        }

        private void OnTimerTick(object sender, EventArgs e)
        {
            _secondsRemaining--;

            if (_secondsRemaining <= 0)
            {
                Close();
                return;
            }

            UpdateCountdownText();
        }

        private void UpdateCountdownText()
        {
            _countdownLabel.Text =
                "Closing automatically in " + _secondsRemaining + " seconds...";
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
    }
}
