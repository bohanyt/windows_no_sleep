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
        private const string DuplicateNoticeMutexName =
            @"Local\WindowsNoSleep-6B4E7D6F-6E39-4C33-9F75-6AF730C57D61-DuplicateNotice";

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
                    return ShowAlreadyRunningNotice();
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                using (var context = new TrayApplicationContext())
                {
                    Application.Run(context);
                }
            }

            return 0;
        }

        private static int ShowAlreadyRunningNotice()
        {
            bool noticeCreated;
            using (var noticeMutex = new Mutex(true, DuplicateNoticeMutexName, out noticeCreated))
            {
                if (!noticeCreated)
                {
                    return 0;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new AlreadyRunningForm());
            }

            return 0;
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
