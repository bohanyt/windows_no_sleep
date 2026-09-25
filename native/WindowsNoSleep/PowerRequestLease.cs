using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WindowsNoSleep
{
    internal sealed class PowerRequestLease : IDisposable
    {
        private IntPtr _handle;
        private bool _requestSet;
        private readonly PowerRequestType _type;
        private bool _disposed;

        private PowerRequestLease(IntPtr handle, PowerRequestType type)
        {
            _handle = handle; _type = type;
        }

        internal bool IsActive
        {
            get { return !_disposed && _handle != IntPtr.Zero && _requestSet; }
        }

        internal static PowerRequestLease AcquireSystemRequired(string reason)
        {
            return Acquire(reason, PowerRequestType.SystemRequired);
        }

        internal static PowerRequestLease AcquireDisplayRequired(string reason)
        {
            return Acquire(reason, PowerRequestType.DisplayRequired);
        }

        private static PowerRequestLease Acquire(string reason, PowerRequestType type)
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

            var lease = new PowerRequestLease(handle, type);
            try
            {
                if (!NativeMethods.PowerSetRequest(handle, type))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "PowerSetRequest(" + type + ") failed.");
                }

                lease._requestSet = true;
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
                if (_requestSet)
                {
                    NativeMethods.PowerClearRequest(_handle, _type);
                    _requestSet = false;
                }

                NativeMethods.CloseHandle(_handle);
                _handle = IntPtr.Zero;
            }
        }
    }
}
