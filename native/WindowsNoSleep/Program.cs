using System;
using System.Linq;
using System.Windows.Forms;

namespace WindowsNoSleep
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            if (args.Any(arg => string.Equals(arg, "--self-test", StringComparison.OrdinalIgnoreCase)))
            {
                return RunSelfTest();
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            using (var context = new TrayApplicationContext())
            {
                Application.Run(context);
            }

            return 0;
        }

        private static int RunSelfTest()
        {
            try
            {
                using (var lease = PowerRequestLease.AcquireSystemRequired(
                    "Windows No Sleep native pilot self-test"))
                {
                    if (!lease.IsActive)
                    {
                        return 2;
                    }
                }

                return 0;
            }
            catch
            {
                return 1;
            }
        }
    }
}
