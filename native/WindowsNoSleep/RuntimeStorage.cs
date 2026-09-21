using System;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Principal;
using System.Text;
using System.Threading;
using Microsoft.Win32;

namespace WindowsNoSleep
{
    internal static class AtomicFiles
    {
        internal static bool Exists(string path)
        {
            try { File.GetAttributes(path); return true; }
            catch (FileNotFoundException) { return false; }
            catch (DirectoryNotFoundException) { return false; }
        }
        internal static T Read<T>(string path)
        {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new IOException("Refusing redirected state file.");
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                if (stream.Length > 65536) throw new IOException("State file exceeds the allowed size.");
                return (T)new DataContractJsonSerializer(typeof(T)).ReadObject(stream);
            }
        }
        internal static void Write<T>(string path, T value)
        {
            string directory = Path.GetDirectoryName(path);
            Directory.CreateDirectory(directory);
            if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0
                || (Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0))
                throw new IOException("Refusing redirected state storage.");
            string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                {
                    new DataContractJsonSerializer(typeof(T)).WriteObject(stream, value);
                    stream.Flush(true);
                }
                if (Exists(path)) File.Replace(temp, path, null);
                else File.Move(temp, path);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }
    internal sealed class NativeJournalStore : IRecoveryStore
    {
        private readonly string _path, _machine, _user;
        internal NativeJournalStore(string directory, string machine, string user)
        {
            _path = Path.Combine(directory, "recovery.json"); _machine = machine; _user = user;
        }
        public bool Exists { get { return AtomicFiles.Exists(_path); } }
        public RecoveryJournal Load()
        {
            if (!Exists) return null;
            var journal = AtomicFiles.Read<RecoveryJournal>(_path);
            if (journal == null) throw new InvalidOperationException("Empty recovery record; it has not been deleted.");
            journal.Validate();
            if (journal.Machine != _machine || journal.User != _user)
                throw new InvalidOperationException("Recovery belongs to another machine/account. No values were changed.");
            return journal;
        }
        public void Save(RecoveryJournal journal)
        {
            if (string.IsNullOrWhiteSpace(_machine) || string.IsNullOrWhiteSpace(_user))
                throw new InvalidOperationException("Cannot establish recovery ownership.");
            var existing = Load();
            if (existing != null && existing.Transaction != journal.Transaction)
                throw new InvalidOperationException("A different recovery transaction is pending.");
            journal.Machine = _machine; journal.User = _user;
            journal.Validate();
            AtomicFiles.Write(_path, journal);
        }
        public void Clear(RecoveryJournal verifiedJournal)
        {
            var current = Load();
            if (current == null) return;
            if (current.Transaction != verifiedJournal.Transaction)
                throw new InvalidOperationException("Recovery record changed during restoration.");
            AtomicFiles.Write(Path.Combine(Path.GetDirectoryName(_path), "last-restore.json"),
                new RestoreRecord { RestoredUtc = DateTime.UtcNow.ToString("o"), Journal = verifiedJournal });
            File.Delete(_path);
        }
        [DataContract]
        private sealed class RestoreRecord
        {
            [DataMember] public string RestoredUtc;
            [DataMember] public RecoveryJournal Journal;
        }
    }
    internal sealed class RuntimeStorage
    {
        internal readonly string DirectoryPath;
        private readonly object _logLock = new object();
        internal RuntimeStorage(string directory) { DirectoryPath = directory; Directory.CreateDirectory(directory); }
        internal AppOptions LoadOptions(out string warning)
        {
            warning = null;
            string path = Path.Combine(DirectoryPath, "settings.json");
            try
            {
                if (!AtomicFiles.Exists(path)) return new AppOptions();
                var options = AtomicFiles.Read<AppOptions>(path);
                if (options == null) throw new InvalidOperationException("Empty settings.");
                options.Validate();
                return options;
            }
            catch (Exception error)
            {
                warning = "Settings could not be read. Basic protection only until settings are saved: " + error.Message;
                return new AppOptions { LidProtection = false, DcTimeoutProtection = false, BlockShutdown = false };
            }
        }
        internal void SaveOptions(AppOptions options)
        {
            options.Validate();
            AtomicFiles.Write(Path.Combine(DirectoryPath, "settings.json"), options);
        }
        internal void Log(string message)
        {
            // WER must not wait for a lock held by the failing application thread.
            if (!Monitor.TryEnter(_logLock, 20)) return;
            try
            {
                string path = Path.Combine(DirectoryPath, "events.log");
                if (File.Exists(path) && new FileInfo(path).Length >= 1024 * 1024)
                {
                    string previous = path + ".previous";
                    if (File.Exists(previous)) File.Delete(previous);
                    File.Move(path, previous);
                }
                File.AppendAllText(path, DateTime.UtcNow.ToString("o") + " " + message.Replace('\r', ' ').Replace('\n', ' ') + Environment.NewLine, Encoding.UTF8);
            }
            catch (Exception) { /* Logging cannot prevent a safety release or journal restore. */ }
            finally { Monitor.Exit(_logLock); }
        }
        internal string ReadLog()
        {
            try { string path = Path.Combine(DirectoryPath, "events.log"); return File.Exists(path) ? File.ReadAllText(path) : "No events recorded."; }
            catch (Exception error) { return error.Message; }
        }
        internal static string DefaultPath { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WindowsNoSleep"); } }
        internal static string UserId { get { using (var id = WindowsIdentity.GetCurrent()) return id.User.Value; } }
        internal static string MachineId
        {
            get
            {
                using (var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography", false))
                {
                    string value = key == null ? null : key.GetValue("MachineGuid") as string;
                    if (string.IsNullOrWhiteSpace(value)) throw new InvalidOperationException("Machine identity for recovery is unavailable.");
                    return value;
                }
            }
        }
    }
    internal sealed class StartupManager
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "WindowsNoSleep.Native";
        private readonly string _command;
        internal StartupManager(string executablePath) { _command = "\"" + executablePath + "\" --autostart"; }
        internal bool Enabled
        {
            get { using (var key = Registry.CurrentUser.OpenSubKey(RunKey, false)) return key != null && string.Equals(key.GetValue(ValueName) as string, _command, StringComparison.OrdinalIgnoreCase); }
        }
        internal void SetEnabled(bool enabled)
        {
            using (var key = Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (key == null) throw new InvalidOperationException("Windows startup settings are unavailable.");
                if (enabled) key.SetValue(ValueName, _command, RegistryValueKind.String);
                else key.DeleteValue(ValueName, false);
            }
            if (Enabled != enabled) throw new IOException("Windows startup change could not be verified.");
        }
    }
}
