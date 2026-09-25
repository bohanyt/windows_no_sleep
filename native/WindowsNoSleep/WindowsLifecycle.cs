using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace WindowsNoSleep
{
    internal sealed class NamedOwnership : IDisposable
    {
        private Mutex _mutex;
        internal bool Acquired { get; private set; }
        internal NamedOwnership(string name)
        {
            _mutex = new Mutex(false, name);
            try { Acquired = _mutex.WaitOne(0); }
            catch (AbandonedMutexException) { Acquired = true; }
        }
        public void Dispose()
        {
            if (_mutex == null) return;
            if (Acquired) { _mutex.ReleaseMutex(); Acquired = false; }
            _mutex.Dispose(); _mutex = null;
        }
    }
    internal static class ShutdownRules
    {
        internal static bool Reject(bool protectedAndSafe, long flags)
        {
            // Do not fight a forced shutdown or an explicit logoff.
            return protectedAndSafe && (flags & 0x40000000L) == 0 && (flags & 0x80000000L) == 0;
        }
    }
    internal sealed class ShutdownWindow : Form, IShutdownGuard
    {
        internal Func<bool> CanBlock = delegate { return false; };
        internal Action SessionEnded = delegate { };
        internal Action<int> PowerChanged = delegate { };
        private readonly Action<string> _log;
        public bool IsArmed { get; private set; }
        internal ShutdownWindow(Action<string> log)
        {
            _log = log;
            Text = "Windows No Sleep - lifecycle";
            ShowInTaskbar = false;
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            var createdHandle = Handle; // A hidden top-level HWND, not HWND_MESSAGE.
        }
        public void Set(bool enabled)
        {
            if (enabled == IsArmed) return;
            if (enabled)
            {
                if (!ShutdownBlockReasonCreate(Handle, "Windows No Sleep is keeping your workloads running. Use Stop Protection or Exit to allow restart/shutdown."))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot register the shutdown reason.");
                IsArmed = true;
            }
            else
            {
                IsArmed = false; // WM_QUERYENDSESSION immediately stops vetoing.
                if (IsHandleCreated && !ShutdownBlockReasonDestroy(Handle))
                {
                    // Destroying the owning HWND also removes its stale reason.
                    DestroyHandle();
                    _log("SHUTDOWN_REASON_DESTROY_FAILED window released");
                }
            }
        }
        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x0011) // WM_QUERYENDSESSION
            {
                bool reject = ShutdownRules.Reject(IsArmed && CanBlock(), message.LParam.ToInt64());
                _log("SESSION_QUERY reject=" + reject + " flags=" + message.LParam.ToInt64());
                message.Result = reject ? IntPtr.Zero : new IntPtr(1);
                return;
            }
            if (message.Msg == 0x0016) // WM_ENDSESSION
            {
                _log("SESSION_END committed=" + (message.WParam != IntPtr.Zero));
                if (message.WParam != IntPtr.Zero) SessionEnded();
                message.Result = IntPtr.Zero;
                return;
            }
            if (message.Msg == 0x0218) // WM_POWERBROADCAST
            {
                PowerChanged(message.WParam.ToInt32());
                message.Result = new IntPtr(1);
                return;
            }
            base.WndProc(ref message);
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing && IsArmed) Set(false);
            base.Dispose(disposing);
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShutdownBlockReasonCreate(IntPtr window, string reason);
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShutdownBlockReasonDestroy(IntPtr window);
    }
    internal sealed class ApplicationRecoveryRegistration : IDisposable
    {
        private readonly RecoveryCallback _callback;
        private readonly Func<Action, bool> _recover;
        private bool _callbackRegistered, _restartRegistered;
        internal bool Ready { get { return _callbackRegistered && _restartRegistered; } }
        internal string Error { get; private set; }
        internal ApplicationRecoveryRegistration(Func<Action, bool> recover)
        {
            _recover = recover; _callback = Recover;
            try
            {
                Marshal.ThrowExceptionForHR(RegisterApplicationRecoveryCallback(_callback, IntPtr.Zero, 5000, 0));
                _callbackRegistered = true;
                // Crash/hang recovery is independent of optional logon autostart.
                Marshal.ThrowExceptionForHR(RegisterApplicationRestart("--recovered", 4 | 8));
                _restartRegistered = true;
            }
            catch (Exception error) { Error = "Windows recovery registration unavailable: " + error.Message; }
        }
        private uint Recover(IntPtr ignored)
        {
            bool success = false;
            try { Pulse(); success = _recover(Pulse); }
            catch { success = false; }
            // Must be last: Windows may terminate the process inside this call.
            ApplicationRecoveryFinished(success);
            return 0;
        }
        private static void Pulse()
        {
            bool cancelled;
            int result = ApplicationRecoveryInProgress(out cancelled);
            if (result < 0 || cancelled) throw new OperationCanceledException("Windows cancelled recovery; the journal remains for next launch.");
        }
        public void Dispose()
        {
            if (_callbackRegistered) { UnregisterApplicationRecoveryCallback(); _callbackRegistered = false; }
            if (_restartRegistered) { UnregisterApplicationRestart(); _restartRegistered = false; }
            GC.KeepAlive(_callback);
        }
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate uint RecoveryCallback(IntPtr parameter);
        [DllImport("kernel32.dll")] private static extern int RegisterApplicationRecoveryCallback(RecoveryCallback callback, IntPtr parameter, uint pingInterval, uint flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern int RegisterApplicationRestart(string commandLine, uint flags);
        [DllImport("kernel32.dll")] private static extern int UnregisterApplicationRecoveryCallback();
        [DllImport("kernel32.dll")] private static extern int UnregisterApplicationRestart();
        [DllImport("kernel32.dll")] private static extern int ApplicationRecoveryInProgress([MarshalAs(UnmanagedType.Bool)] out bool cancelled);
        [DllImport("kernel32.dll")] private static extern void ApplicationRecoveryFinished([MarshalAs(UnmanagedType.Bool)] bool success);
    }
}
