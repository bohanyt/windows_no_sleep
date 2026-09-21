using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32;

namespace WindowsNoSleep
{
    internal interface IScreenSaverProtection
    {
        bool Active { get; }
        bool Pending { get; }
        string Warning { get; }
        string Detail { get; }
        void Start(bool enabled);
        void Poll();
        void Restore();
    }
    internal sealed class ScreenSaverState
    {
        internal bool Enabled, Secure, SettingsManaged;
        internal int Timeout;
        internal string ProfileStamp, LockWarning;
    }
    internal interface IScreenSaverPlatform
    {
        string User { get; }
        string Logon { get; }
        ScreenSaverState Read();
        void SetActive(bool enabled);
    }
    internal interface IScreenSaverStore
    {
        bool Exists { get; }
        ScreenSaverRecord Load();
        void Save(ScreenSaverRecord record);
        void Clear(ScreenSaverRecord record, string disposition);
    }
    internal sealed class MachineInactivityState
    {
        internal bool Exists;
        internal uint Seconds;
    }
    internal interface IMachineInactivityPlatform
    {
        bool IsElevated { get; }
        MachineInactivityState ReadMachineInactivity();
        void SetMachineInactivity(uint seconds);
    }
    internal interface IMachineInactivityStore
    {
        bool Exists { get; }
        MachineInactivityRecord Load();
        void Save(MachineInactivityRecord record);
        void Clear(MachineInactivityRecord record, string disposition);
    }
    [DataContract]
    internal sealed class MachineInactivityRecord
    {
        [DataMember(IsRequired = true)] public int Version = 1;
        [DataMember(IsRequired = true)] public string Product = "WindowsNoSleep.MachineInactivity";
        [DataMember(IsRequired = true)] public string Transaction = Guid.NewGuid().ToString("D");
        [DataMember(IsRequired = true)] public string Machine;
        [DataMember(IsRequired = true)] public string User;
        [DataMember(IsRequired = true)] public uint OriginalSeconds;
        internal void Validate()
        {
            Guid value;
            if (Version != 1 || Product != "WindowsNoSleep.MachineInactivity"
                || !Guid.TryParse(Transaction, out value) || string.IsNullOrWhiteSpace(Machine)
                || string.IsNullOrWhiteSpace(User) || OriginalSeconds == 0)
                throw new InvalidOperationException("Invalid machine-inactivity recovery record; no policy write was attempted.");
        }
    }
    [DataContract]
    internal sealed class ScreenSaverRecord
    {
        [DataMember(IsRequired = true)] public int Version = 1;
        [DataMember(IsRequired = true)] public string Product = "WindowsNoSleep.ScreenSaver";
        [DataMember(IsRequired = true)] public string Transaction = Guid.NewGuid().ToString("D");
        [DataMember(IsRequired = true)] public string User;
        [DataMember(IsRequired = true)] public string Logon;
        [DataMember(IsRequired = true)] public string ProfileStamp;
        [DataMember(IsRequired = true)] public bool OriginalActive;
        internal void Validate()
        {
            Guid value;
            if (Version != 1 || Product != "WindowsNoSleep.ScreenSaver" || !Guid.TryParse(Transaction, out value)
                || string.IsNullOrEmpty(User) || string.IsNullOrEmpty(Logon) || string.IsNullOrEmpty(ProfileStamp)
                || ProfileStamp.Length > 256 || !OriginalActive)
                throw new InvalidOperationException("Invalid screensaver recovery record; no settings were changed.");
        }
    }
    internal sealed class ScreenSaverProtection : IScreenSaverProtection
    {
        private readonly IScreenSaverPlatform _platform;
        private readonly IScreenSaverStore _store;
        private readonly IMachineInactivityPlatform _machine;
        private readonly IMachineInactivityStore _machineStore;
        private readonly Action<string> _log;
        private string _profile, _lockObserved;
        private bool _machineActive;
        private uint _machineOriginal;
        internal bool RecoveryReady = true;
        internal string RecoveryError;
        public bool Active { get; private set; }
        public bool Pending
        {
            get
            {
                try { return _store.Exists || (_machineStore != null && _machineStore.Exists); }
                catch { return true; }
            }
        }
        public string Warning { get; private set; }
        public string Detail { get; private set; }
        internal ScreenSaverProtection(IScreenSaverPlatform platform, IScreenSaverStore store, Action<string> log,
            IMachineInactivityPlatform machine = null, IMachineInactivityStore machineStore = null)
        {
            _platform = platform; _store = store; _log = log; _machine = machine; _machineStore = machineStore;
            Detail = "Not started";
        }
        public void Start(bool enabled)
        {
            Restore(); Warning = null; _lockObserved = null; _machineActive = false; _machineOriginal = 0;
            if (!enabled) { Detail = "Off - screensaver and automatic-lock settings follow Windows"; return; }
            try
            {
                var before = _platform.Read();
                if (before.Enabled && before.SettingsManaged)
                    throw new InvalidOperationException("Windows policy manages the screensaver. This app does not override that policy.");
                if (before.Enabled)
                {
                    if (!RecoveryReady) throw new InvalidOperationException("Recovery unavailable: " + RecoveryError);
                    var record = new ScreenSaverRecord { User = _platform.User, Logon = _platform.Logon,
                        ProfileStamp = before.ProfileStamp, OriginalActive = true };
                    record.Validate();
                    _store.Save(record);
                    var check = _platform.Read();
                    if (check.ProfileStamp != before.ProfileStamp || check.SettingsManaged || !check.Enabled)
                        throw new InvalidOperationException("Screensaver settings changed during startup.");
                    _platform.SetActive(false);
                }

                if (_machine != null && _machineStore != null)
                {
                    var machineBefore = _machine.ReadMachineInactivity();
                    if (machineBefore.Exists && machineBefore.Seconds > 0)
                    {
                        if (_machine.IsElevated)
                        {
                            if (!RecoveryReady) throw new InvalidOperationException("Recovery unavailable: " + RecoveryError);
                            var machineRecord = new MachineInactivityRecord { OriginalSeconds = machineBefore.Seconds };
                            _machineStore.Save(machineRecord);
                            var machineCheck = _machine.ReadMachineInactivity();
                            if (!machineCheck.Exists || machineCheck.Seconds != machineBefore.Seconds)
                                throw new InvalidOperationException("Machine inactivity policy changed during startup.");
                            _machine.SetMachineInactivity(0);
                            var machineAfter = _machine.ReadMachineInactivity();
                            if (!machineAfter.Exists || machineAfter.Seconds != 0)
                                throw new InvalidOperationException("Windows did not verify the temporary machine-inactivity override.");
                            _machineActive = true;
                            _machineOriginal = machineBefore.Seconds;
                            _log("MACHINE_INACTIVITY_ACTIVE originalSeconds=" + _machineOriginal + " temporary=0");
                        }
                    }
                }

                var after = _platform.Read();
                if (after.Enabled || after.ProfileStamp != before.ProfileStamp)
                    throw new InvalidOperationException("Windows did not verify screensaver suppression.");
                _profile = before.ProfileStamp;
                Active = true;
                Warning = after.LockWarning;
                Detail = _machineActive
                    ? "Active - screensaver and local machine inactivity auto-lock prevented"
                    : "Active - ordinary screensaver and its automatic sign-in prompt prevented";
                _log("SCREENSAVER_ACTIVE verifiedDisabled=true original=" + before.Enabled + " timeoutSeconds=" + before.Timeout
                    + " passwordOnResume=" + before.Secure + " machineInactivityOverridden=" + _machineActive
                    + " lockLimit=" + (Warning ?? "none detected"));
            }
            catch (Exception error)
            {
                string rollback = null;
                try { Restore(); } catch (Exception restore) { rollback = restore.Message; }
                Warning = error.Message + (rollback == null ? "" : " Restore pending: " + rollback);
                Detail = "Unavailable - " + Warning;
                _log("SCREENSAVER_UNAVAILABLE " + Warning);
                if (rollback != null) throw new InvalidOperationException(Warning, error);
            }
        }
        public void Poll()
        {
            if (!Active) return;
            try
            {
                var state = _platform.Read();
                if (_machineActive && _machine != null)
                {
                    var machineState = _machine.ReadMachineInactivity();
                    if (!machineState.Exists || machineState.Seconds != 0)
                    {
                        Restore();
                        Warning = "Windows machine inactivity policy changed outside this app; the temporary override stopped.";
                        Detail = "Unavailable - " + Warning;
                        return;
                    }
                }
                if (state.Enabled || state.ProfileStamp != _profile || (state.SettingsManaged && Pending))
                {
                    Restore();
                    Warning = "Screensaver settings changed outside this app; suppression stopped. Check Windows settings.";
                    Detail = "Unavailable - " + Warning;
                }
                else Warning = Join(state.LockWarning, _lockObserved);
            }
            catch (Exception error)
            {
                Warning = "Cannot verify screensaver/idle-lock protection: " + error.Message;
                Detail = "Verification failed - " + Warning;
            }
        }
        internal void ObserveSessionLock()
        {
            if (!Active) return;
            _lockObserved = "Windows locked this session (manual or another trigger). Automatic-lock prevention is not verified.";
            Warning = Join(Warning, _lockObserved);
            _log("SESSION_LOCK_OBSERVED screensaverSuppressed=" + Active + " cause=unknown_manual_or_OS");
        }
        public void Restore()
        {
            Active = false;
            var errors = new List<string>();
            try { RestoreMachineInactivity(); } catch (Exception error) { errors.Add("Machine inactivity: " + error.Message); }
            try { RestoreScreenSaver(); } catch (Exception error) { errors.Add("Screensaver: " + error.Message); }
            if (errors.Count != 0) throw new InvalidOperationException(string.Join("; ", errors));
            Warning = null;
        }
        private void RestoreMachineInactivity()
        {
            _machineActive = false; _machineOriginal = 0;
            if (_machine == null || _machineStore == null) return;
            var record = _machineStore.Load();
            if (record == null) return;
            record.Validate();
            var current = _machine.ReadMachineInactivity();
            if (!current.Exists)
                throw new InvalidOperationException("Machine inactivity policy disappeared; recovery record preserved instead of guessing.");
            if (current.Seconds == record.OriginalSeconds)
            {
                _machineStore.Clear(record, "Original machine inactivity value was already restored");
                _log("MACHINE_INACTIVITY_RESTORE_VERIFIED original=" + record.OriginalSeconds + " after=" + current.Seconds);
                return;
            }
            if (current.Seconds != 0)
                throw new InvalidOperationException("Machine inactivity policy changed externally to " + current.Seconds
                    + " seconds; original " + record.OriginalSeconds + " preserved in recovery record.");
            if (!_machine.IsElevated)
                throw new InvalidOperationException("Run Windows No Sleep as administrator to restore the original machine inactivity policy ("
                    + record.OriginalSeconds + " seconds).");
            _machine.SetMachineInactivity(record.OriginalSeconds);
            var after = _machine.ReadMachineInactivity();
            if (!after.Exists || after.Seconds != record.OriginalSeconds)
                throw new InvalidOperationException("Machine inactivity policy restore was not verified; recovery record preserved.");
            _machineStore.Clear(record, "Original machine inactivity value restored and read back");
            _log("MACHINE_INACTIVITY_RESTORE_VERIFIED original=" + record.OriginalSeconds + " after=" + after.Seconds);
        }
        private void RestoreScreenSaver()
        {
            var record = _store.Load();
            if (record == null) { Detail = "Off - no temporary screensaver setting remains"; return; }
            record.Validate();
            if (record.User != _platform.User)
                throw new InvalidOperationException("Screensaver recovery belongs to a different account; record preserved.");
            if (record.Logon != _platform.Logon)
            {
                _store.Clear(record, "Previous logon ended; volatile change expired; profile was never modified");
                _log("SCREENSAVER_RECOVERY_EXPIRED newLogon=true profileWasNotModified=true");
                Detail = "Off - previous logon's temporary change expired"; return;
            }
            var current = _platform.Read();
            if (current.ProfileStamp != record.ProfileStamp)
                throw new InvalidOperationException("User screensaver profile changed; recovery conflict preserved instead of overwriting it.");
            if (!current.Enabled)
            {
                if (current.SettingsManaged)
                    throw new InvalidOperationException("New screensaver policy prevents exact restoration; recovery record preserved.");
                _platform.SetActive(record.OriginalActive);
            }
            var after = _platform.Read();
            if (after.Enabled != record.OriginalActive || after.ProfileStamp != record.ProfileStamp)
                throw new InvalidOperationException("Screensaver restore was not verified; recovery record preserved.");
            _store.Clear(record, "Original session screensaver value restored and read back");
            _log("SCREENSAVER_RESTORE_VERIFIED original=" + record.OriginalActive + " after=" + after.Enabled);
            Detail = "Off - original screensaver and automatic-lock settings restored and verified";
        }
        private static string Join(string left, string right)
        {
            if (string.IsNullOrWhiteSpace(left)) return right;
            if (string.IsNullOrWhiteSpace(right) || left.Contains(right)) return left;
            return left + " " + right;
        }
    }
    internal sealed class ScreenSaverJournalStore : IScreenSaverStore
    {
        private readonly string _path;
        internal ScreenSaverJournalStore(string directory) { _path = Path.Combine(directory, "desktop-recovery.json"); }
        public bool Exists { get { return AtomicFiles.Exists(_path); } }
        public ScreenSaverRecord Load()
        {
            if (!Exists) return null;
            var record = AtomicFiles.Read<ScreenSaverRecord>(_path);
            if (record == null) throw new InvalidOperationException("Empty screensaver recovery record; preserved.");
            record.Validate(); return record;
        }
        public void Save(ScreenSaverRecord record)
        {
            record.Validate();
            if (Exists) throw new InvalidOperationException("Screensaver recovery is already pending.");
            AtomicFiles.Write(_path, record);
        }
        public void Clear(ScreenSaverRecord record, string disposition)
        {
            var current = Load();
            if (current == null || current.Transaction != record.Transaction)
                throw new InvalidOperationException("Screensaver recovery record changed during restore.");
            AtomicFiles.Write(Path.Combine(Path.GetDirectoryName(_path), "last-desktop-restore.json"),
                new Receipt { Utc = DateTime.UtcNow.ToString("o"), Disposition = disposition, Record = record });
            File.Delete(_path);
        }
        [DataContract] private sealed class Receipt
        {
            [DataMember] public string Utc;
            [DataMember] public string Disposition;
            [DataMember] public ScreenSaverRecord Record;
        }
    }
    internal sealed class MachineInactivityJournalStore : IMachineInactivityStore
    {
        private readonly string _path, _machine, _user;
        internal MachineInactivityJournalStore(string directory, string machine, string user)
        {
            _path = Path.Combine(directory, "machine-lock-recovery.json"); _machine = machine; _user = user;
        }
        public bool Exists { get { return AtomicFiles.Exists(_path); } }
        public MachineInactivityRecord Load()
        {
            if (!Exists) return null;
            var record = AtomicFiles.Read<MachineInactivityRecord>(_path);
            if (record == null) throw new InvalidOperationException("Empty machine-inactivity recovery record; preserved.");
            record.Validate();
            if (record.Machine != _machine || record.User != _user)
                throw new InvalidOperationException("Machine-inactivity recovery belongs to another machine/account; no policy write was attempted.");
            return record;
        }
        public void Save(MachineInactivityRecord record)
        {
            if (string.IsNullOrWhiteSpace(_machine) || string.IsNullOrWhiteSpace(_user))
                throw new InvalidOperationException("Cannot establish machine-inactivity recovery ownership.");
            if (Exists) throw new InvalidOperationException("Machine-inactivity recovery is already pending.");
            record.Machine = _machine; record.User = _user; record.Validate();
            AtomicFiles.Write(_path, record);
        }
        public void Clear(MachineInactivityRecord record, string disposition)
        {
            var current = Load();
            if (current == null || current.Transaction != record.Transaction)
                throw new InvalidOperationException("Machine-inactivity recovery record changed during restore.");
            AtomicFiles.Write(Path.Combine(Path.GetDirectoryName(_path), "last-machine-lock-restore.json"),
                new Receipt { Utc = DateTime.UtcNow.ToString("o"), Disposition = disposition, Record = record });
            File.Delete(_path);
        }
        [DataContract] private sealed class Receipt
        {
            [DataMember] public string Utc;
            [DataMember] public string Disposition;
            [DataMember] public MachineInactivityRecord Record;
        }
    }
    internal sealed class WindowsScreenSaverPlatform : IScreenSaverPlatform, IMachineInactivityPlatform
    {
        // Microsoft: SystemParametersInfoW / SPI_GETSCREENSAVEACTIVE (0x10),
        // SPI_SETSCREENSAVEACTIVE (0x11), fWinIni=0 leaves the user profile intact.
        // https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-systemparametersinfow
        private const string PolicyDesktop = @"Software\Policies\Microsoft\Windows\Control Panel\Desktop";
        private static readonly string[] ProfileNames = { "ScreenSaveActive", "ScreenSaveTimeOut", "ScreenSaverIsSecure", "SCRNSAVE.EXE" };
        public string User { get { return RuntimeStorage.UserId; } }
        public string Logon
        {
            get
            {
                // TOKEN_STATISTICS.AuthenticationId is a LUID identifying this
                // logon, unlike a reusable Terminal Services session number.
                using (var identity = WindowsIdentity.GetCurrent())
                {
                    int length;
                    GetTokenInformation(identity.Token, 10, IntPtr.Zero, 0, out length);
                    if (length < 16 || length > 4096) throw new InvalidOperationException("Logon identity unavailable.");
                    IntPtr memory = Marshal.AllocHGlobal(length);
                    try
                    {
                        if (!GetTokenInformation(identity.Token, 10, memory, length, out length))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "Read logon identity");
                        return Process.GetCurrentProcess().SessionId + ":"
                            + unchecked((uint)Marshal.ReadInt32(memory, 12)).ToString("X8")
                            + unchecked((uint)Marshal.ReadInt32(memory, 8)).ToString("X8");
                    }
                    finally { Marshal.FreeHGlobal(memory); }
                }
            }
        }
        public ScreenSaverState Read()
        {
            var result = new ScreenSaverState { Enabled = GetParameter(0x0010) != 0,
                Secure = GetParameter(0x0076) != 0, Timeout = GetParameter(0x000e) };
            var stamp = new StringBuilder();
            using (var key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop", false))
            {
                foreach (string name in ProfileNames)
                {
                    object value = key == null ? null : key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                    stamp.Append(name).Append('|').Append(value == null ? "<absent>" : key.GetValueKind(name) + ":" + value).Append('\n');
                }
            }
            using (var hash = SHA256.Create())
                result.ProfileStamp = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(stamp.ToString()))).Replace("-", "");
            var warnings = new List<string>();
            foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
            {
                using (var key = hive.OpenSubKey(PolicyDesktop, false))
                {
                    if (key != null && ProfileNames.Any(name => key.GetValue(name) != null))
                    { result.SettingsManaged = true; warnings.Add("Screensaver settings are managed by Windows policy."); }
                }
            }
            var inactivity = ReadMachineInactivity();
            if (inactivity.Exists && inactivity.Seconds > 0)
                warnings.Add("Windows machine inactivity policy requires lock after " + inactivity.Seconds
                    + " seconds. Run Windows No Sleep as administrator to temporarily disable it while Protection is active.");
            long deviceLock = Number(Registry.LocalMachine, @"SOFTWARE\Microsoft\PolicyManager\current\device\DeviceLock", "MaxInactivityTimeDeviceLock");
            if (deviceLock > 0) warnings.Add("Device/MDM policy requires automatic lock after " + deviceLock + " minutes; not overridden.");
            if (Number(Registry.CurrentUser, @"Software\Microsoft\Windows NT\CurrentVersion\Winlogon", "EnableGoodbye") > 0)
                warnings.Add("Dynamic Lock is enabled; it can still lock this session.");
            result.LockWarning = warnings.Count == 0 ? null : string.Join(" ", warnings.Distinct());
            return result;
        }
        public bool IsElevated
        {
            get
            {
                using (var identity = WindowsIdentity.GetCurrent())
                    return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
            }
        }
        public MachineInactivityState ReadMachineInactivity()
        {
            const string path = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System";
            using (var hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
            using (var key = hive.OpenSubKey(path, false))
            {
                if (key == null) return new MachineInactivityState();
                object value = key.GetValue("InactivityTimeoutSecs", null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                if (value == null) return new MachineInactivityState();
                if (key.GetValueKind("InactivityTimeoutSecs") != RegistryValueKind.DWord)
                    throw new InvalidOperationException("Machine inactivity policy has an unexpected registry type.");
                long number;
                if (!long.TryParse(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture), out number)
                    || number < 0 || number > uint.MaxValue)
                    throw new InvalidOperationException("Machine inactivity policy value is invalid.");
                return new MachineInactivityState { Exists = true, Seconds = (uint)number };
            }
        }
        public void SetMachineInactivity(uint seconds)
        {
            if (!IsElevated)
                throw new UnauthorizedAccessException("Run Windows No Sleep as administrator to change the local machine inactivity policy.");
            const string path = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System";
            using (var hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
            using (var key = hive.OpenSubKey(path, true))
            {
                if (key == null) throw new InvalidOperationException("Windows machine inactivity policy key is unavailable.");
                key.SetValue("InactivityTimeoutSecs", unchecked((int)seconds), RegistryValueKind.DWord);
                key.Flush();
            }
        }
        public void SetActive(bool enabled)
        {
            // Only the ordinary session screensaver enable flag is changed.
            // Never SPI_SETSCREENSAVESECURE, Winlogon, Policies, SendInput or a password setting.
            if (!SetParameter(0x0011, enabled ? 1u : 0u, IntPtr.Zero, 0))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Change temporary screensaver state (unlock Windows first)");
        }
        private static int GetParameter(uint action)
        {
            int value;
            if (!ReadParameter(action, 0, out value, 0))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Read screensaver state");
            return value;
        }
        private static long Number(RegistryKey hive, string path, string name)
        {
            using (var key = hive.OpenSubKey(path, false))
            {
                object value = key == null ? null : key.GetValue(name);
                if (value == null) return 0;
                long number;
                if (!long.TryParse(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture), out number))
                    throw new InvalidOperationException("Cannot inspect lock setting " + name);
                return number;
            }
        }
        [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)] private static extern bool ReadParameter(uint action, uint parameter, out int value, uint flags);
        [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetParameter(uint action, uint parameter, IntPtr value, uint flags);
        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetTokenInformation(IntPtr token, int informationClass, IntPtr data, int length, out int returned);
    }
}
