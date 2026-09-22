using System;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace WindowsNoSleep
{
    internal static class Program
    {
        private const string InstanceName = @"Local\WindowsNoSleep-6B4E7D6F-6E39-4C33-9F75-6AF730C57D61";
        private const string NoticeName = InstanceName + "-DuplicateNotice";
        [STAThread]
        private static int Main(string[] args)
        {
            // Privileged helper exits before normal user settings, mutex/tray, or recovery initialization.
            if (args.Length == 2 && args[0] == "--machine-inactivity-helper")
                return WindowsScreenSaverPlatform.RunMachineInactivityHelper(args[1]);
            // Tests exit before production settings, registry, screensaver or policy initialization.
            if (args.Length == 1 && args[0] == "--self-test") return RunSelfTest();
            if (args.Length == 2 && args[0] == "--test-suite")
            {
                int core = SelfTests.Run(args[1]);
                int desktop = ScreenSaverTests.Run(args[1]);
                return core != 0 ? core : desktop;
            }
            if (args.Any(arg => arg != "--autostart" && arg != "--recovered")) return 64;
            bool quietDuplicate = args.Length != 0;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
            try
            {
                using (var owner = new NamedOwnership(InstanceName))
                {
                    if (!owner.Acquired) return quietDuplicate ? 0 : ShowAlreadyRunning();
                    string directory = RuntimeStorage.DefaultPath;
                    Directory.CreateDirectory(directory);
                    FileStream fileOwner;
                    try { fileOwner = new FileStream(Path.Combine(directory, "owner.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
                    catch (IOException error)
                    {
                        if ((error.HResult & 0xffff) == 32) return quietDuplicate ? 0 : ShowAlreadyRunning();
                        throw;
                    }
                    using (fileOwner)
                    using (var context = new TrayApplicationContext(directory))
                    {
                        UnhandledExceptionEventHandler recover = delegate { context.RecoverForCrash(null); };
                        AppDomain.CurrentDomain.UnhandledException += recover;
                        try { context.Initialize(); Application.Run(context); }
                        finally { AppDomain.CurrentDomain.UnhandledException -= recover; }
                    }
                }
                return 0;
            }
            catch (Exception error)
            {
                MessageBox.Show("Windows No Sleep could not start safely. Any pending recovery record has been preserved.\n\n" + error.Message,
                    "Windows No Sleep", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 1;
            }
        }
        private static int ShowAlreadyRunning()
        {
            using (var notice = new NamedOwnership(NoticeName))
            {
                if (!notice.Acquired) return 0;
                using (var form = new AlreadyRunningForm()) Application.Run(form);
            }
            return 0;
        }
        private static int RunSelfTest()
        {
            try
            {
                using (var lease = PowerRequestLease.AcquireSystemRequired("Windows No Sleep hosted non-mutating self-test"))
                    return lease.IsActive ? 0 : 2;
            }
            catch { return 1; }
        }
    }
}
