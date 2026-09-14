Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('WindowsNoSleep.Interop.NativeMethods' -as [type])) {
    $references = @(
        [System.Windows.Forms.Form].Assembly.Location,
        [System.Drawing.Icon].Assembly.Location
    ) | Select-Object -Unique

    Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace WindowsNoSleep.Interop
{
    public enum PowerRequestType
    {
        DisplayRequired = 0,
        SystemRequired = 1,
        AwayModeRequired = 2,
        ExecutionRequired = 3
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct ReasonContext
    {
        public UInt32 Version;
        public UInt32 Flags;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string SimpleReasonString;
    }

    public static class NativeMethods
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr PowerCreateRequest(ref ReasonContext Context);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PowerSetRequest(IntPtr PowerRequest, PowerRequestType RequestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PowerClearRequest(IntPtr PowerRequest, PowerRequestType RequestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShutdownBlockReasonCreate(IntPtr hWnd, string pwszReason);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShutdownBlockReasonDestroy(IntPtr hWnd);
    }

    public sealed class ShutdownHostForm : Form
    {
        public bool BlockShutdown { get; set; }
        public event EventHandler ShutdownBlocked;

        public ShutdownHostForm()
        {
            BlockShutdown = false;
            ShowInTaskbar = false;
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            Opacity = 0.0;
            Width = 1;
            Height = 1;
            StartPosition = FormStartPosition.Manual;
            Location = new Point(-32000, -32000);
            Text = "Windows No Sleep Host";
        }

        protected override void SetVisibleCore(bool value)
        {
            base.SetVisibleCore(false);
        }

        protected override void WndProc(ref Message m)
        {
            const int WM_QUERYENDSESSION = 0x0011;

            if (m.Msg == WM_QUERYENDSESSION && BlockShutdown)
            {
                EventHandler handler = ShutdownBlocked;
                if (handler != null)
                {
                    handler(this, EventArgs.Empty);
                }

                m.Result = IntPtr.Zero;
                return;
            }

            base.WndProc(ref m);
        }
    }
}
'@
}

Export-ModuleMember -Function @()
