using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Threading;

namespace WindowsNoSleep
{
    // Runs only via --test-suite <report>. No production tray, power-policy writes,
    // startup registry entries, shutdown attempts or production recovery files.
    internal static class SelfTests
    {
        private sealed class Case { internal string Name; internal Action Body; }
        private static readonly List<Case> Cases = new List<Case>();
        private static void Add(string name, Action body) { Cases.Add(new Case { Name = name, Body = body }); }
        private static void Assert(bool condition, string reason = "Assertion failed") { if (!condition) throw new Exception(reason); }
        private static void Throws(Action body)
        {
            bool threw = false;
            try { body(); } catch (Exception) { threw = true; }
            Assert(threw, "Expected a fail-closed error.");
        }
        private static RecoveryJournal Copy(RecoveryJournal value)
        {
            if (value == null) return null;
            using (var stream = new MemoryStream())
            {
                var serializer = new DataContractJsonSerializer(typeof(RecoveryJournal));
                serializer.WriteObject(stream, value); stream.Position = 0;
                return (RecoveryJournal)serializer.ReadObject(stream);
            }
        }
        private static PowerSnapshot Laptop(int percent = 80, bool ac = true)
        {
            return new PowerSnapshot { ReadSucceeded = true, CapabilitiesKnown = true, OnAc = ac, HasBattery = true,
                Percent = percent, CriticalThreshold = 5, LidPresent = true, HibernateAvailable = true, ModernStandby = true };
        }
        private sealed class Store : IRecoveryStore
        {
            internal RecoveryJournal Data;
            internal readonly List<string> Trace;
            internal bool Broken, FailClear;
            internal int Saves, FailSaveAt;
            internal Store(List<string> trace) { Trace = trace; }
            public bool Exists { get { return Broken || Data != null; } }
            public RecoveryJournal Load()
            {
                if (Broken) throw new IOException("Corrupt journal");
                return Copy(Data);
            }
            public void Save(RecoveryJournal journal)
            {
                if (++Saves == FailSaveAt) throw new IOException("Disk write failed");
                journal.Validate(); Data = Copy(journal); Trace.Add("Save");
            }
            public void Clear(RecoveryJournal journal)
            {
                if (FailClear) throw new IOException("Clear failed");
                Assert(Data != null && Data.Transaction == journal.Transaction, "Must clear only this journal");
                Trace.Add("Clear"); Data = null;
            }
        }
        private sealed class Policy : IPowerPolicy
        {
            internal static readonly Guid OriginalScheme = new Guid("11111111-2222-3333-4444-555555555555");
            internal Guid Current = OriginalScheme;
            internal readonly Dictionary<string, uint> Values = new Dictionary<string, uint>
                { { PolicyKeys.LidAc, 1 }, { PolicyKeys.LidDc, 2 }, { PolicyKeys.SleepDc, 1200 }, { PolicyKeys.HibernateDc, 7200 } };
            internal readonly Dictionary<string, uint> Originals;
            private readonly Store _store;
            private readonly List<string> _trace;
            internal bool Denied, WriteThenThrow, IgnoreWrites, FailRefresh;
            internal string FailRestoreKey;
            internal int Writes;
            internal Action<string, uint> AfterWrite;
            internal Policy(Store store, List<string> trace) { _store = store; _trace = trace; Originals = new Dictionary<string, uint>(Values); }
            public Guid ActiveScheme() { return Current; }
            public uint Read(Guid scheme, string key)
            {
                Assert(scheme == OriginalScheme, "Must not silently migrate to another scheme");
                Assert(PolicyKeys.IsAllowed(key), "Forbidden setting read"); return Values[key];
            }
            public void CheckWrite(string key) { if (Denied) throw new UnauthorizedAccessException("Policy denied"); }
            public void Write(Guid scheme, string key, uint value)
            {
                Assert(scheme == OriginalScheme, "Write targets original scheme only");
                CheckWrite(key);
                var journal = _store.Load();
                Assert(journal != null && journal.Entries.Any(entry => entry.Key == key && entry.Attempted), "Every write needs a persisted attempted entry");
                if (key == FailRestoreKey && value != 0) throw new IOException("Injected restore failure");
                Writes++; _trace.Add("Write:" + key + "=" + value);
                if (!IgnoreWrites) Values[key] = value;
                if (AfterWrite != null) AfterWrite(key, value);
                if (WriteThenThrow && value == 0) { WriteThenThrow = false; throw new IOException("Write succeeded but provider threw"); }
            }
            public void RefreshIfActive(Guid scheme)
            {
                if (Current != scheme) { _trace.Add("RefreshSkippedInactive"); return; }
                _trace.Add("Refresh");
                if (FailRefresh) throw new IOException("Refresh failed");
            }
            internal bool Restored { get { return Originals.All(pair => Values[pair.Key] == pair.Value); } }
        }
        private sealed class Sensor : IPowerSensor
        {
            internal PowerSnapshot Value = Laptop();
            public PowerSnapshot ReadPower() { return Value; }
        }
        private sealed class Guard : IShutdownGuard
        {
            private readonly List<string> _trace;
            internal bool FailArm;
            public bool IsArmed { get; private set; }
            internal Guard(List<string> trace) { _trace = trace; }
            public void Set(bool enabled)
            {
                if (enabled && FailArm) throw new IOException("Guard unavailable");
                IsArmed = enabled; _trace.Add(enabled ? "Guard+" : "Guard-");
            }
        }
        private sealed class Lease : IDisposable
        {
            private Action _release;
            internal Lease(Action release) { _release = release; }
            public void Dispose() { if (_release != null) { _release(); _release = null; } }
        }
        private sealed class Rig
        {
            internal readonly List<string> Trace = new List<string>();
            internal readonly Store Store;
            internal readonly Policy Policy;
            internal readonly Sensor Sensor = new Sensor();
            internal readonly Guard Guard;
            internal readonly PolicyTransaction Transaction;
            internal readonly ProtectionController Core;
            internal int Leases, Acquires, DisplayLeases, DisplayAcquires;
            internal bool FailDisplay;
            internal Rig(AppOptions options = null)
            {
                Store = new Store(Trace); Policy = new Policy(Store, Trace); Guard = new Guard(Trace);
                Transaction = new PolicyTransaction(Policy, Store, Trace.Add);
                Core = new ProtectionController(options ?? new AppOptions(), Sensor, Transaction, Guard, delegate
                {
                    Leases++; Acquires++; Trace.Add("Awake+");
                    return new Lease(delegate { Leases--; Trace.Add("Awake-"); });
                }, Trace.Add, null, delegate
                {
                    DisplayAcquires++;
                    if (FailDisplay) throw new IOException("Injected display request failure");
                    DisplayLeases++; Trace.Add("Display+");
                    return new Lease(delegate { DisplayLeases--; Trace.Add("Display-"); });
                }) { PolicyRecoveryReady = true };
            }
            internal IList<string> Keys { get { return new[] { PolicyKeys.LidAc, PolicyKeys.LidDc, PolicyKeys.SleepDc, PolicyKeys.HibernateDc }; } }
            internal void Apply() { Transaction.Apply(Keys); }
        }
        internal static int Run(string reportPath)
        {
            Cases.Clear(); RegisterBattery(); RegisterTransactions(); RegisterController(); RegisterStorageAndOwnership();
            int failed = 0;
            var text = new StringBuilder("# Native V1 automated tests\n\nAll policy and shutdown providers below are fakes. No physical laptop acceptance is claimed.\n\n");
            foreach (Case test in Cases)
            {
                try { test.Body(); text.AppendLine("PASS " + test.Name); }
                catch (Exception error) { failed++; text.AppendLine("FAIL " + test.Name + ": " + error); }
            }
            text.AppendLine("\nTOTAL=" + Cases.Count + " PASSED=" + (Cases.Count - failed) + " FAILED=" + failed);
            try { File.WriteAllText(Path.GetFullPath(reportPath), text.ToString(), Encoding.UTF8); }
            catch { return 2; }
            return failed == 0 ? 0 : 1;
        }
        private static void RegisterBattery()
        {
            Add("battery defaults 15 percent", delegate { Assert(BatteryRules.Threshold(15, 5) == 15); });
            Add("battery cannot disable base safety", delegate { Assert(BatteryRules.Threshold(0, null) == 15); });
            Add("critical threshold plus five", delegate { Assert(BatteryRules.Threshold(15, 20) == 25); });
            Add("pathological critical threshold clamps safely", delegate { Assert(BatteryRules.Threshold(15, 99) == 100); });
            Add("invalid critical threshold ignored", delegate { Assert(BatteryRules.Threshold(15, 101) == 15); });
            Add("invalid requested upper threshold clamped", delegate { Assert(BatteryRules.Threshold(150, null) == 95); });
            Add("DC enters safety exactly at threshold", delegate { Assert(BatteryRules.MustPause(Laptop(15, false), 15, false)); });
            Add("DC above threshold initially continues", delegate { Assert(!BatteryRules.MustPause(Laptop(16, false), 15, false)); });
            Add("hysteresis prevents resume at 19", delegate { Assert(BatteryRules.MustPause(Laptop(19, false), 15, true)); });
            Add("hysteresis permits resume at 20", delegate { Assert(!BatteryRules.MustPause(Laptop(20, false), 15, true)); });
            Add("AC permits resume", delegate { Assert(!BatteryRules.MustPause(Laptop(1, true), 15, true)); });
            Add("critical battery flag wins above threshold", delegate { var power = Laptop(50, false); power.Critical = true; Assert(BatteryRules.MustPause(power, 15, false)); });
            Add("unknown source pauses battery protection", delegate { var power = Laptop(); power.OnAc = null; Assert(BatteryRules.MustPause(power, 15, false)); });
            Add("unknown battery charge pauses protection", delegate { var power = Laptop(80, false); power.Percent = null; Assert(BatteryRules.MustPause(power, 15, false)); });
            Add("unreadable power fails safe", delegate { Assert(BatteryRules.MustPause(new PowerSnapshot(), 15, false)); });
            Add("no-battery desktop needs no battery pause", delegate { Assert(!BatteryRules.MustPause(new PowerSnapshot { ReadSucceeded = true, HasBattery = false }, 15, false)); });
            Add("all four policy keys on laptop", delegate { Assert(PolicyKeys.Requested(new AppOptions(), Laptop()).Count == 4); });
            Add("DC disabled never modifies DC keys", delegate { var keys = PolicyKeys.Requested(new AppOptions { ProtectOnBattery = false }, Laptop()); Assert(keys.SequenceEqual(new[] { PolicyKeys.LidAc })); });
            Add("absent hiberfile skips hibernate policy", delegate { var power = Laptop(); power.HibernateAvailable = false; Assert(!PolicyKeys.Requested(new AppOptions(), power).Contains(PolicyKeys.HibernateDc)); });
            Add("desktop no lid or battery policy writes", delegate { Assert(PolicyKeys.Requested(new AppOptions(), new PowerSnapshot()).Count == 0); });
            Add("forbidden keys rejected", delegate { Assert(!PolicyKeys.IsAllowed("CriticalBatteryAction")); Throws(delegate { PolicyKeys.Setting("PowerButton"); }); });
        }
        private static void RegisterTransactions()
        {
            Add("write-ahead and exact restore for every key", delegate { var r = new Rig(); r.Apply(); Assert(r.Policy.Values.All(pair => pair.Value == 0)); Assert(r.Store.Exists); r.Transaction.Restore(); Assert(r.Policy.Restored && !r.Store.Exists); Assert(r.Trace.First() == "Save"); });
            Add("unchanged values never written or journalled", delegate { var r = new Rig(); foreach (string key in r.Keys) r.Policy.Values[key] = 0; r.Apply(); Assert(r.Policy.Writes == 0 && r.Store.Saves == 0); r.Transaction.Restore(); });
            Add("permission denial before first mutation", delegate { var r = new Rig(); r.Policy.Denied = true; Throws(r.Apply); Assert(r.Policy.Writes == 0 && !r.Store.Exists); });
            Add("journal initial save failure makes zero writes", delegate { var r = new Rig(); r.Store.FailSaveAt = 1; Throws(r.Apply); Assert(r.Policy.Writes == 0 && !r.Store.Exists); });
            Add("journal interrupted mid-apply rolls back", delegate { var r = new Rig(); r.Store.FailSaveAt = 3; Throws(r.Apply); Assert(r.Policy.Restored && !r.Store.Exists); });
            Add("provider throws after real write still restored", delegate { var r = new Rig(); r.Policy.WriteThenThrow = true; Throws(r.Apply); Assert(r.Policy.Restored && !r.Store.Exists); });
            Add("readback failure is never accepted", delegate { var r = new Rig(); r.Policy.IgnoreWrites = true; Throws(r.Apply); Assert(!r.Transaction.Active && !r.Store.Exists); });
            Add("restore error preserves journal and restores other keys", delegate { var r = new Rig(); r.Apply(); r.Policy.FailRestoreKey = PolicyKeys.LidAc; Throws(delegate { r.Transaction.Restore(); }); Assert(r.Store.Exists && r.Policy.Values[PolicyKeys.LidAc] == 0 && r.Policy.Values[PolicyKeys.SleepDc] == 1200); });
            Add("pending recovery prevents another snapshot", delegate { var r = new Rig(); r.Apply(); string id = r.Store.Data.Transaction; r.Policy.FailRestoreKey = PolicyKeys.LidAc; Throws(delegate { r.Transaction.Restore(); }); Throws(r.Apply); Assert(r.Store.Data.Transaction == id); });
            Add("restore can resume after transient failure", delegate { var r = new Rig(); r.Apply(); r.Policy.FailRestoreKey = PolicyKeys.LidAc; Throws(delegate { r.Transaction.Restore(); }); r.Policy.FailRestoreKey = null; r.Transaction.Restore(); Assert(r.Policy.Restored && !r.Store.Exists); });
            Add("failed refresh keeps recovery even after value reads", delegate { var r = new Rig(); r.Policy.FailRefresh = true; Throws(r.Apply); Assert(r.Store.Exists); r.Policy.FailRefresh = false; r.Transaction.Restore(); Assert(!r.Store.Exists && r.Policy.Restored); });
            Add("failed journal clear can be retried safely", delegate { var r = new Rig(); r.Apply(); r.Store.FailClear = true; Throws(delegate { r.Transaction.Restore(); }); Assert(r.Store.Exists && r.Policy.Restored); r.Store.FailClear = false; r.Transaction.Restore(); Assert(!r.Store.Exists); });
            Add("external value is preserved not overwritten", delegate { var r = new Rig(); r.Apply(); r.Policy.Values[PolicyKeys.SleepDc] = 999; Throws(delegate { r.Transaction.Restore(); }); Assert(r.Policy.Values[PolicyKeys.SleepDc] == 999 && r.Store.Exists && r.Policy.Values[PolicyKeys.LidAc] == 1); });
            Add("plan drift does not switch active plan back", delegate { var r = new Rig(); r.Apply(); var changed = Guid.NewGuid(); r.Policy.Current = changed; Assert(r.Transaction.HasDrift()); r.Transaction.Restore(); Assert(r.Policy.Current == changed && r.Policy.Restored && r.Trace.Contains("RefreshSkippedInactive")); });
            Add("cancellation after first write restores it", delegate { var r = new Rig(); bool wanted = true; r.Policy.AfterWrite = delegate(string key, uint value) { if (value == 0) wanted = false; }; Throws(delegate { r.Transaction.Apply(r.Keys, delegate { return wanted; }); }); Assert(r.Policy.Restored && !r.Store.Exists); });
            Add("reentrant restore cannot delete live write-ahead record", delegate { var r = new Rig(); bool wanted = true; r.Policy.AfterWrite = delegate(string key, uint value) { if (value == 0) { Throws(delegate { r.Transaction.Restore(); }); Assert(r.Store.Exists); wanted = false; } }; Throws(delegate { r.Transaction.Apply(r.Keys, delegate { return wanted; }); }); Assert(r.Policy.Restored && !r.Store.Exists); });
            Add("WER cancellation preserves pending recovery", delegate { var r = new Rig(); r.Apply(); Throws(delegate { r.Transaction.Restore(delegate { throw new OperationCanceledException(); }); }); Assert(r.Store.Exists); r.Transaction.Restore(); Assert(r.Policy.Restored); });
            for (int attempted = 0; attempted <= 4; attempted++)
            {
                int count = attempted;
                for (int beforeWrite = 0; beforeWrite <= 1; beforeWrite++)
                {
                    int applied = Math.Max(0, count - beforeWrite);
                    Add("next-launch crash boundary attempted=" + count + " applied=" + applied, delegate
                    {
                        var r = new Rig(); var journal = new RecoveryJournal { Scheme = Policy.OriginalScheme.ToString("D") };
                        for (int index = 0; index < r.Keys.Count; index++)
                        {
                            string key = r.Keys[index];
                            journal.Entries.Add(new RecoveryEntry { Key = key, Original = r.Policy.Values[key], Attempted = index < count });
                            if (index < applied) r.Policy.Values[key] = 0;
                        }
                        r.Store.Save(journal);
                        new PolicyTransaction(r.Policy, r.Store, r.Trace.Add).Restore();
                        Assert(r.Policy.Restored && !r.Store.Exists);
                    });
                }
            }
            Add("large sleep values restore losslessly", delegate { var r = new Rig(); r.Policy.Values[PolicyKeys.SleepDc] = uint.MaxValue; r.Apply(); r.Transaction.Restore(); Assert(r.Policy.Values[PolicyKeys.SleepDc] == uint.MaxValue); });
            Add("unknown lid action stops before writes", delegate { var r = new Rig(); r.Policy.Values[PolicyKeys.LidAc] = 4; Throws(r.Apply); Assert(r.Policy.Writes == 0 && !r.Store.Exists); });
            Add("corrupt journal never triggers guessed restoration", delegate { var r = new Rig(); r.Store.Broken = true; Throws(delegate { r.Transaction.Restore(); }); Assert(r.Policy.Writes == 0 && r.Store.Exists); });
        }
        private static void RegisterController()
        {
            Add("Modern Standby AC keeps SystemRequired only", delegate { var r = new Rig(); r.Core.Start(); Assert(r.Leases == 1 && r.DisplayLeases == 0 && r.DisplayAcquires == 0 && r.Core.State == ProtectionState.Protected); r.Core.Stop(); });
            Add("qualifying DC Start acquires display request", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.Core.Start(); Assert(r.Leases == 1 && r.DisplayLeases == 1 && r.DisplayAcquires == 1 && r.Core.DisplayRequiredActive && r.Core.State == ProtectionState.Protected); r.Core.Stop(); });
            Add("live AC to DC acquires display without controller restart", delegate { var r = new Rig(); r.Core.Start(); r.Sensor.Value = Laptop(80, false); r.Core.Poll(); Assert(r.DisplayAcquires == 1 && r.DisplayLeases == 1 && r.Acquires == 1 && r.Leases == 1); r.Core.Stop(); });
            Add("repeated DC polls do not reacquire or log display request", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.Core.Start(); r.Trace.Clear(); r.Core.Poll(); r.Core.Poll(); Assert(r.DisplayAcquires == 1 && !r.Trace.Any(value => value.StartsWith("DISPLAY_REQUIRED_"))); r.Core.Stop(); });
            Add("DC to AC releases display but retains SystemRequired", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.Core.Start(); r.Sensor.Value = Laptop(); r.Core.Poll(); Assert(r.DisplayLeases == 0 && r.Leases == 1 && r.Acquires == 1 && r.Core.State == ProtectionState.Protected && r.Trace.Contains("DISPLAY_REQUIRED_RELEASED reason=ac")); r.Core.Stop(); });
            Add("battery without Modern Standby skips display request", delegate { var r = new Rig(); var power = Laptop(80, false); power.ModernStandby = false; r.Sensor.Value = power; r.Core.Start(); Assert(r.Leases == 1 && r.DisplayAcquires == 0 && r.Core.State == ProtectionState.Protected); r.Core.Stop(); });
            Add("Modern Standby without battery skips display request", delegate { var r = new Rig(); var power = Laptop(80, false); power.HasBattery = false; r.Sensor.Value = power; r.Core.Start(); Assert(r.Leases == 1 && r.DisplayAcquires == 0); r.Core.Stop(); });
            Add("disabled battery protection pauses without display request", delegate { var r = new Rig(new AppOptions { ProtectOnBattery = false }); r.Sensor.Value = Laptop(80, false); r.Core.Start(); Assert(r.Leases == 0 && r.DisplayAcquires == 0 && r.Core.State == ProtectionState.Stopped); r.Core.Stop(); });
            Add("Battery Safety releases display request", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.Core.Start(); r.Sensor.Value = Laptop(15, false); r.Core.Poll(); Assert(r.DisplayLeases == 0 && r.Leases == 0 && r.Core.State == ProtectionState.BatterySafety && r.Trace.Contains("DISPLAY_REQUIRED_RELEASED reason=battery_safety")); r.Core.Stop(); });
            Add("Stop releases display request", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.Core.Start(); r.Core.Stop(); Assert(r.DisplayLeases == 0 && r.Leases == 0 && r.Trace.Contains("DISPLAY_REQUIRED_RELEASED reason=stop")); });
            Add("Suspend releases and qualifying Resume reacquires display", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.Core.Start(); r.Core.Suspend(); Assert(r.DisplayLeases == 0 && r.Trace.Contains("DISPLAY_REQUIRED_RELEASED reason=suspend")); r.Core.Resume(); Assert(r.DisplayLeases == 1 && r.DisplayAcquires == 2); r.Core.Stop(); });
            Add("Resume on AC does not reacquire display", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.Core.Start(); r.Core.Suspend(); r.Sensor.Value = Laptop(); r.Core.Resume(); Assert(r.DisplayLeases == 0 && r.DisplayAcquires == 1 && r.Leases == 1); r.Core.Stop(); });
            Add("crash terminal recovery releases display", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.Core.Start(); Assert(r.Core.RecoverForCrash(null)); Assert(r.DisplayLeases == 0 && r.Leases == 0 && r.Trace.Contains("DISPLAY_REQUIRED_RELEASED reason=cleanup")); r.Core.Start(); Assert(r.DisplayAcquires == 1); });
            Add("terminal drift cleanup releases display", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.Core.Start(); r.Policy.Values[PolicyKeys.SleepDc] = 999; r.Core.Poll(); Assert(r.DisplayLeases == 0 && r.Leases == 0 && r.Core.State == ProtectionState.Degraded && r.Trace.Contains("DISPLAY_REQUIRED_RELEASED reason=cleanup")); });
            Add("display acquire failure degrades without retry spam or losing system request", delegate { var r = new Rig(); r.Sensor.Value = Laptop(80, false); r.FailDisplay = true; r.Core.Start(); Assert(r.Core.State == ProtectionState.Degraded && r.Core.IsAwake && r.Leases == 1 && r.DisplayLeases == 0 && r.Core.Detail.Contains("Display request unavailable")); r.Core.Poll(); r.Core.Poll(); Assert(r.DisplayAcquires == 1 && r.Trace.Count(value => value.StartsWith("DISPLAY_REQUIRED_FAILED")) == 1); r.Sensor.Value = Laptop(); r.Core.Poll(); r.Sensor.Value = Laptop(80, false); r.FailDisplay = false; r.Core.Poll(); Assert(r.DisplayAcquires == 2 && r.DisplayLeases == 1 && r.Core.State == ProtectionState.Protected); r.Core.Stop(); });
            Add("Start is idempotent", delegate { var r = new Rig(); r.Core.Start(); r.Core.Start(); r.Core.Poll(); Assert(r.Leases == 1 && r.Acquires == 1 && r.Policy.Writes == 4 && r.Core.State == ProtectionState.Protected); r.Core.Stop(); });
            Add("Stop clears blockers and restores", delegate { var r = new Rig(); r.Core.Start(); r.Core.Stop(); Assert(r.Leases == 0 && !r.Guard.IsArmed && r.Policy.Restored && !r.Store.Exists && r.Core.State == ProtectionState.Stopped); });
            Add("explicit Stop stays stopped across power changes", delegate { var r = new Rig(); r.Core.Start(); r.Core.Stop(); r.Sensor.Value = Laptop(80, false); r.Core.Poll(); r.Sensor.Value = Laptop(); r.Core.Poll(); Assert(!r.Core.Wanted && r.Leases == 0); });
            Add("battery safety releases before restore", delegate
            {
                var r = new Rig(); r.Core.Start(); r.Trace.Clear(); r.Sensor.Value = Laptop(15, false); r.Core.Poll();
                Assert(r.Core.State == ProtectionState.BatterySafety && !r.Guard.IsArmed && r.Leases == 0 && r.Policy.Restored);
                int restore = r.Trace.FindIndex(value => value.StartsWith("Write:"));
                Assert(r.Trace.IndexOf("Guard-") < restore && r.Trace.IndexOf("Awake-") < restore);
            });
            Add("battery hysteresis and AC resume integrate", delegate { var r = new Rig(); r.Core.Start(); r.Sensor.Value = Laptop(15, false); r.Core.Poll(); r.Sensor.Value = Laptop(18, false); r.Core.Poll(); Assert(r.Leases == 0); r.Sensor.Value = Laptop(18, true); r.Core.Poll(); Assert(r.Leases == 1 && r.Core.State == ProtectionState.Protected); r.Core.Stop(); });
            Add("battery safety despite restore error never blocks shutdown", delegate { var r = new Rig(); r.Core.Start(); r.Policy.FailRestoreKey = PolicyKeys.LidAc; r.Sensor.Value = Laptop(10, false); r.Core.Poll(); Assert(r.Leases == 0 && !r.Core.MayBlockShutdown() && !r.Guard.IsArmed && r.Store.Exists); });
            Add("unreadable power status releases running protection", delegate { var r = new Rig(); r.Core.Start(); r.Sensor.Value = new PowerSnapshot(); r.Core.Poll(); Assert(r.Leases == 0 && !r.Guard.IsArmed && r.Policy.Restored); });
            Add("disabled DC protection resumes only on AC", delegate { var r = new Rig(new AppOptions { ProtectOnBattery = false }); r.Core.Start(); r.Sensor.Value = Laptop(80, false); r.Core.Poll(); Assert(r.Leases == 0); r.Sensor.Value = Laptop(); r.Core.Poll(); Assert(r.Leases == 1); r.Core.Stop(); });
            Add("unsafe initial battery never creates protection owner", delegate { var r = new Rig(); r.Sensor.Value = Laptop(1, false); r.Core.Start(); Assert(r.Acquires == 0 && r.Policy.Writes == 0 && !r.Guard.IsArmed); });
            Add("shutdown query reads fresh battery before next timer", delegate { var r = new Rig(); r.Core.Start(); Assert(r.Core.MayBlockShutdown()); r.Sensor.Value = Laptop(1, false); Assert(!r.Core.MayBlockShutdown()); r.Core.Stop(); });
            Add("guard failures expose degraded basic protection", delegate { var r = new Rig(); r.Guard.FailArm = true; r.Core.Start(); Assert(r.Core.IsAwake && !r.Core.GuardActive && r.Core.State == ProtectionState.Degraded); r.Core.Stop(); });
            Add("policy capability unavailable leaves basic protection only", delegate { var r = new Rig(); r.Core.PolicyRecoveryReady = false; r.Core.PolicyRecoveryError = "ARR unavailable"; r.Core.Start(); Assert(r.Core.IsAwake && r.Policy.Writes == 0 && r.Core.State == ProtectionState.Degraded); r.Core.Stop(); });
            Add("startup recovery completes before awake acquire", delegate { var r = new Rig(); r.Apply(); r.Trace.Clear(); r.Core.Start(); Assert(r.Trace.IndexOf("Clear") < r.Trace.IndexOf("Awake+")); r.Core.Stop(); Assert(r.Policy.Restored); });
            Add("corrupt startup recovery fails closed", delegate { var r = new Rig(); r.Store.Broken = true; r.Core.Start(); Assert(r.Core.State == ProtectionState.Degraded && r.Acquires == 0 && r.Policy.Writes == 0); });
            Add("external drift pauses instead of fighting new settings", delegate { var r = new Rig(); r.Core.Start(); r.Policy.Values[PolicyKeys.SleepDc] = 999; r.Core.Poll(); Assert(!r.Core.Wanted && !r.Core.IsAwake && !r.Guard.IsArmed && r.Store.Exists && r.Policy.Values[PolicyKeys.SleepDc] == 999); });
            Add("explicit suspend releases and resume reacquires", delegate { var r = new Rig(); r.Core.Start(); r.Core.Suspend(); Assert(r.Policy.Restored && r.Leases == 0); r.Core.Resume(); Assert(r.Acquires == 2 && r.Leases == 1); r.Core.Stop(); });
            Add("option changes restore before saving and reacquiring", delegate { var r = new Rig(); r.Core.Start(); var options = new AppOptions { LidProtection = false, DcTimeoutProtection = false }; r.Core.ChangeOptions(options, delegate { Assert(r.Policy.Restored && r.Leases == 0 && !r.Guard.IsArmed); }); Assert(r.Core.IsAwake && !r.Store.Exists); r.Core.Stop(); });
            Add("failed settings persistence leaves protection stopped", delegate { var r = new Rig(); r.Core.Start(); Throws(delegate { r.Core.ChangeOptions(new AppOptions(), delegate { throw new IOException(); }); }); Assert(r.Leases == 0 && r.Policy.Restored); });
            Add("crash callback restoration is terminal", delegate { var r = new Rig(); r.Core.Start(); Assert(r.Core.RecoverForCrash(null)); Assert(r.Policy.Restored && r.Leases == 0 && !r.Core.MayBlockShutdown()); r.Core.Start(); Assert(r.Leases == 0); r.Core.Stop(); });
            Add("forced shutdown and logoff are never vetoed", delegate { Assert(ShutdownRules.Reject(true, 0)); Assert(!ShutdownRules.Reject(true, 0x40000000L)); Assert(!ShutdownRules.Reject(true, 0x80000000L)); Assert(!ShutdownRules.Reject(false, 0)); });
            Add("reentrant Stop during apply restores and releases", delegate { var r = new Rig(); bool once = false; r.Policy.AfterWrite = delegate(string key, uint value) { if (value == 0 && !once) { once = true; r.Core.Stop(); } }; r.Core.Start(); Assert(!r.Core.IsAwake && !r.Guard.IsArmed && r.Policy.Restored && !r.Store.Exists); });
        }
        private static void WithDirectory(Action<string> body)
        {
            string directory = Path.Combine(Path.GetTempPath(), "WindowsNoSleep-FAKE-TEST-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            try { body(directory); }
            finally { Directory.Delete(directory, true); } // Only this unique fake-test directory.
        }
        private static RecoveryJournal Journal()
        {
            return new RecoveryJournal { Scheme = Policy.OriginalScheme.ToString("D"), Entries = new List<RecoveryEntry>
                { new RecoveryEntry { Key = PolicyKeys.SleepDc, Original = 1200, Attempted = true } } };
        }
        private static void RegisterStorageAndOwnership()
        {
            Add("journal atomically persists and writes restore receipt", delegate { WithDirectory(delegate(string path) { var store = new NativeJournalStore(path, "fake-machine", "fake-user"); var journal = Journal(); store.Save(journal); Assert(store.Load().Entries[0].Original == 1200); store.Save(journal); store.Clear(journal); Assert(!store.Exists && File.Exists(Path.Combine(path, "last-restore.json"))); }); });
            Add("foreign-account journal is preserved", delegate { WithDirectory(delegate(string path) { var store = new NativeJournalStore(path, "fake-machine", "fake-user"); store.Save(Journal()); var other = new NativeJournalStore(path, "fake-machine", "other-user"); Throws(delegate { other.Load(); }); Assert(store.Exists); }); });
            Add("foreign-machine journal is preserved", delegate { WithDirectory(delegate(string path) { var store = new NativeJournalStore(path, "fake-machine", "fake-user"); store.Save(Journal()); Throws(delegate { new NativeJournalStore(path, "other-machine", "fake-user").Load(); }); Assert(store.Exists); }); });
            Add("corrupt disk journal is not erased", delegate { WithDirectory(delegate(string path) { File.WriteAllText(Path.Combine(path, "recovery.json"), "not json"); var store = new NativeJournalStore(path, "fake-machine", "fake-user"); Throws(delegate { store.Load(); }); Assert(store.Exists); }); });
            Add("journal version rejected", delegate { var journal = Journal(); journal.Version = 99; Throws(journal.Validate); });
            Add("journal unknown setting rejected", delegate { var journal = Journal(); journal.Entries[0].Key = "PowerButton"; Throws(journal.Validate); });
            Add("journal unexpected applied value rejected", delegate { var journal = Journal(); journal.Entries[0].Applied = 7; Throws(journal.Validate); });
            Add("journal duplicate key rejected", delegate { var journal = Journal(); journal.Entries.Add(journal.Entries[0]); Throws(journal.Validate); });
            Add("journal unknown product rejected", delegate { var journal = Journal(); journal.Product = "LegacyPowerShell"; Throws(journal.Validate); });
            Add("missing machine identity prevents snapshot", delegate { WithDirectory(delegate(string path) { var store = new NativeJournalStore(path, null, "fake-user"); Throws(delegate { store.Save(Journal()); }); Assert(!store.Exists); }); });
            Add("existing transaction cannot be overwritten", delegate { WithDirectory(delegate(string path) { var store = new NativeJournalStore(path, "fake-machine", "fake-user"); var original = Journal(); store.Save(original); Throws(delegate { store.Save(Journal()); }); Assert(store.Load().Transaction == original.Transaction); }); });
            Add("missing settings keep intended defaults without writing", delegate { WithDirectory(delegate(string path) { var storage = new RuntimeStorage(path); string warning; var options = storage.LoadOptions(out warning); Assert(warning == null && options.BatterySafetyPercent == 15 && options.BlockShutdown && options.LidProtection); Assert(!File.Exists(Path.Combine(path, "settings.json"))); }); });
            Add("corrupt settings use basic-only defaults and preserve file", delegate { WithDirectory(delegate(string path) { string file = Path.Combine(path, "settings.json"); File.WriteAllText(file, "bad"); string warning; var options = new RuntimeStorage(path).LoadOptions(out warning); Assert(warning != null && !options.LidProtection && !options.DcTimeoutProtection && !options.BlockShutdown); Assert(File.ReadAllText(file) == "bad"); }); });
            Add("settings roundtrip", delegate { WithDirectory(delegate(string path) { var storage = new RuntimeStorage(path); storage.SaveOptions(new AppOptions { BatterySafetyPercent = 25, ProtectOnBattery = false }); string warning; var options = storage.LoadOptions(out warning); Assert(options.BatterySafetyPercent == 25 && !options.ProtectOnBattery && warning == null); }); });
            Add("startup command quotes path with spaces", delegate { var manager = new StartupManager(@"C:\Test App\WindowsNoSleep.exe"); string command = (string)typeof(StartupManager).GetField("_command", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(manager); Assert(command == "\"C:\\Test App\\WindowsNoSleep.exe\" --autostart"); });
            Add("single owner excludes another thread", delegate
            {
                string name = @"Local\WindowsNoSleep.TEST." + Guid.NewGuid().ToString("N"); bool acquired = true; Exception error = null;
                using (var first = new NamedOwnership(name))
                {
                    Assert(first.Acquired);
                    var thread = new Thread(delegate() { try { using (var second = new NamedOwnership(name)) acquired = second.Acquired; } catch (Exception exception) { error = exception; } });
                    thread.IsBackground = true; thread.Start(); Assert(thread.Join(3000), "Mutex test timed out"); Assert(error == null && !acquired);
                }
                using (var next = new NamedOwnership(name)) Assert(next.Acquired, "Clean exit must release ownership");
            });
        }
    }
}
