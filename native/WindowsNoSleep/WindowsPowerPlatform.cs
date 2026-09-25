using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WindowsNoSleep
{
    // The only power values this application is permitted to write.
    internal static class PolicyKeys
    {
        internal const string LidAc = "LidAc";
        internal const string LidDc = "LidDc";
        internal const string SleepDc = "SleepDc";
        internal const string HibernateDc = "HibernateDc";
        internal static bool IsAllowed(string key)
        {
            return key == LidAc || key == LidDc || key == SleepDc || key == HibernateDc;
        }
        internal static bool IsDc(string key) { return key != LidAc; }
        internal static Guid Group(string key)
        {
            if (!IsAllowed(key)) throw new InvalidOperationException("Unapproved power setting.");
            return new Guid(key == LidAc || key == LidDc
                ? "4f971e89-eebd-4455-a8de-9e59040e7347" : "238c9fa8-0aad-41ed-83f4-97be242c8f20");
        }
        internal static Guid Setting(string key)
        {
            if (!IsAllowed(key)) throw new InvalidOperationException("Unapproved power setting.");
            return new Guid(key == LidAc || key == LidDc ? "5ca83367-6e45-459f-a27b-476b1d01c936"
                : key == SleepDc ? "29f6c1db-86da-48c5-9fdb-f2b67b1f44da" : "9d7815a6-7ee4-497e-8888-515a05f02364");
        }
        internal static IList<string> Requested(AppOptions options, PowerSnapshot power)
        {
            var keys = new List<string>();
            if (options.LidProtection && power.LidPresent)
            {
                keys.Add(LidAc);
                if (options.ProtectOnBattery) keys.Add(LidDc);
            }
            if (options.DcTimeoutProtection && options.ProtectOnBattery && power.HasBattery)
            {
                keys.Add(SleepDc);
                if (power.HibernateAvailable) keys.Add(HibernateDc);
            }
            return keys;
        }
    }

    internal sealed class WindowsPowerPlatform : IPowerPolicy, IPowerSensor
    {
        public Guid ActiveScheme()
        {
            IntPtr pointer;
            Check(PowerGetActiveScheme(IntPtr.Zero, out pointer), "Read active power plan");
            if (pointer == IntPtr.Zero) throw new InvalidOperationException("Windows returned no active power plan.");
            try { return (Guid)Marshal.PtrToStructure(pointer, typeof(Guid)); }
            finally { LocalFree(pointer); }
        }
        public uint Read(Guid scheme, string key)
        {
            var group = PolicyKeys.Group(key);
            var setting = PolicyKeys.Setting(key);
            uint value;
            Check(PolicyKeys.IsDc(key)
                ? PowerReadDCValueIndex(IntPtr.Zero, ref scheme, ref group, ref setting, out value)
                : PowerReadACValueIndex(IntPtr.Zero, ref scheme, ref group, ref setting, out value), "Read " + key);
            return value;
        }
        public void CheckWrite(string key)
        {
            var setting = PolicyKeys.Setting(key);
            Check(PowerSettingAccessCheck(PolicyKeys.IsDc(key) ? 1 : 0, ref setting), "Policy permits " + key);
        }
        public void Write(Guid scheme, string key, uint value)
        {
            CheckWrite(key); // Never attempt to bypass Group Policy.
            var group = PolicyKeys.Group(key);
            var setting = PolicyKeys.Setting(key);
            Check(PolicyKeys.IsDc(key)
                ? PowerWriteDCValueIndex(IntPtr.Zero, ref scheme, ref group, ref setting, value)
                : PowerWriteACValueIndex(IntPtr.Zero, ref scheme, ref group, ref setting, value), "Write " + key);
        }
        public void RefreshIfActive(Guid scheme)
        {
            // PowerWrite* needs a refresh. Never select an inactive/superseded plan.
            if (ActiveScheme() != scheme) return;
            Check(PowerSetActiveScheme(IntPtr.Zero, ref scheme), "Refresh current power plan");
            if (ActiveScheme() != scheme) throw new InvalidOperationException("Power plan changed during refresh.");
        }
        public PowerSnapshot ReadPower()
        {
            var result = new PowerSnapshot();
            PowerStatus status;
            Capabilities capabilities;
            bool statusOk = GetSystemPowerStatus(out status);
            bool capsOk = GetPwrCapabilities(out capabilities);
            result.ReadSucceeded = statusOk;
            result.LidPresent = capsOk && capabilities.LidPresent != 0;
            result.HibernateAvailable = capsOk && capabilities.HiberFilePresent != 0;
            result.ModernStandby = capsOk && capabilities.AoAc != 0;
            result.CapabilitiesKnown = capsOk;
            if (statusOk)
            {
                result.OnAc = status.AcLineStatus == 1 ? (bool?)true : status.AcLineStatus == 0 ? false : (bool?)null;
                result.HasBattery = status.BatteryFlag == 255
                    ? (!capsOk || capabilities.SystemBatteriesPresent != 0)
                    : (status.BatteryFlag & 128) == 0;
                result.Percent = status.BatteryLifePercent <= 100 ? (int?)status.BatteryLifePercent : null;
                result.Critical = status.BatteryFlag != 255 && (status.BatteryFlag & 4) != 0;
            }
            if (result.HasBattery)
            {
                try
                {
                    var scheme = ActiveScheme();
                    var group = new Guid("e73a048d-bf27-4f12-9731-8b2076e8891f");
                    // BATLEVELCRIT, not BATACTIONCRIT. Read only; never change either.
                    var setting = new Guid("9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469");
                    uint threshold;
                    if (PowerReadDCValueIndex(IntPtr.Zero, ref scheme, ref group, ref setting, out threshold) == 0 && threshold <= 100)
                        result.CriticalThreshold = (int)threshold;
                }
                catch (Exception) { /* Battery flag + base threshold remain authoritative. */ }
            }
            return result;
        }
        private static void Check(uint error, string operation)
        {
            if (error != 0) throw new Win32Exception((int)error, operation + " failed (Windows error " + error + ").");
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct PowerStatus
        {
            internal byte AcLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag;
            internal uint BatteryLifeTime, BatteryFullLifeTime;
        }
        // WinNT.h SYSTEM_POWER_CAPABILITIES has a stable 76-byte layout. The
        // processor/spare union is deliberately opaque; only these ABI offsets
        // are used. SDK field offsets are asserted by hosted tests.
        [StructLayout(LayoutKind.Explicit, Size = 76)]
        internal struct Capabilities
        {
            [FieldOffset(2)] internal byte LidPresent;
            [FieldOffset(8)] internal byte HiberFilePresent;
            [FieldOffset(20)] internal byte AoAc;
            [FieldOffset(30)] internal byte SystemBatteriesPresent;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetSystemPowerStatus(out PowerStatus status);
        [DllImport("powrprof.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.U1)]
        private static extern bool GetPwrCapabilities(out Capabilities capabilities);
        [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
        [DllImport("powrprof.dll")] private static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
        [DllImport("powrprof.dll")] private static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);
        [DllImport("powrprof.dll")] private static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);
        [DllImport("powrprof.dll")] private static extern uint PowerWriteACValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, uint value);
        [DllImport("powrprof.dll")] private static extern uint PowerWriteDCValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, uint value);
        [DllImport("powrprof.dll")] private static extern uint PowerSetActiveScheme(IntPtr root, ref Guid scheme);
        [DllImport("powrprof.dll")] private static extern uint PowerSettingAccessCheck(int access, ref Guid setting);
    }
}
