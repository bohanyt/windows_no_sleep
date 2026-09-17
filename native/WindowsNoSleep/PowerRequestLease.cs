using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WindowsNoSleep
{
    internal sealed class PowerRequestLease : IDisposable
    {
        private IntPtr _handle;
        private bool _systemRequiredSet;
        private bool _disposed;

        private PowerRequestLease(IntPtr handle)
        {
            _handle = handle;
        }

        internal bool IsActive
        {
            get { return !_disposed && _handle != IntPtr.Zero && _systemRequiredSet; }
        }

        internal static PowerRequestLease AcquireSystemRequired(string reason)
        {
            if (string.IsNullOrWhiteSpace(reason))
            {
                throw new ArgumentException("A non-empty power-request reason is required.", nameof(reason));
            }

            var context = new ReasonContext
            {
                Version = 0,
                Flags = 1,
                SimpleReasonString = reason
            };

            var handle = NativeMethods.PowerCreateRequest(ref context);
            if (handle == new IntPtr(-1))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "PowerCreateRequest failed.");
            }

            var lease = new PowerRequestLease(handle);
            try
            {
                if (!NativeMethods.PowerSetRequest(handle, PowerRequestType.SystemRequired))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "PowerSetRequest(SystemRequired) failed.");
                }

                lease._systemRequiredSet = true;
                return lease;
            }
            catch
            {
                lease.Dispose();
                throw;
            }
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;

            if (_handle != IntPtr.Zero)
            {
                if (_systemRequiredSet)
                {
                    NativeMethods.PowerClearRequest(_handle, PowerRequestType.SystemRequired);
                    _systemRequiredSet = false;
                }

                NativeMethods.CloseHandle(_handle);
                _handle = IntPtr.Zero;
            }
        }
    }
}
