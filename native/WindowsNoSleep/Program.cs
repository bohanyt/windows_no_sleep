using System;
using System.Linq;
using System.Threading;
using System.Windows.Forms;

namespace WindowsNoSleep
{
    internal static class Program
    {
        private const string SingleInstanceMutexName =
            @"Local\WindowsNoSleep-6B4E7D6F-6E39-4C33-9F75-6AF730C57D61";
        private const string ShowSettingsEventName =
            @"Local\WindowsNoSleep-6B4E7D6F-6E39-4C33-9F75-6AF730C57D61-ShowSettings";

        [STAThread]
        private static int Main(string[] args)
        {
            if (args.Any(arg => string.Equals(arg, "--self-test", StringComparison.OrdinalIgnoreCase)))
            {
                return RunSelfTest();
            }

            bool createdNew;
            using (var singleInstanceMutex = new Mutex(true, SingleInstanceMutexName, out createdNew))
            {
                if (!createdNew)
                {
                    SignalExistingInstance();
                    return 0;
                }

                using (var showSettingsEvent = new EventWaitHandle(
                    false,
                    EventResetMode.AutoReset,
                    ShowSettingsEventName))
                {
                    Application.EnableVisualStyles();
                    Application.SetCompatibleTextRenderingDefault(false);

                    using (var context = new TrayApplicationContext(showSettingsEvent))
                    {
                        Application.Run(context);
                    }
                }
            }

            return 0;
        }

        private static void SignalExistingInstance()
        {
            // The first instance creates this event immediately after taking the
            // mutex. Retry briefly so a fast double-click cannot race that setup.
            for (var attempt = 0; attempt < 20; attempt++)
            {
                try
                {
                    using (var showSettingsEvent = EventWaitHandle.OpenExisting(ShowSettingsEventName))
                    {
                        showSettingsEvent.Set();
                        return;
                    }
                }
                catch (WaitHandleCannotBeOpenedException)
                {
                    Thread.Sleep(50);
                }
                catch (UnauthorizedAccessException)
                {
                    return;
                }
            }
        }

        private static int RunSelfTest()
        {
            try
            {
                using (var lease = PowerRequestLease.AcquireSystemRequired(
                    "Windows No Sleep self-test"))
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
