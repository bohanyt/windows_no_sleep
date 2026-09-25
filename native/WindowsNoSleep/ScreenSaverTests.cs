using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.Serialization.Json;
using System.Text;

namespace WindowsNoSleep
{
    // Entire suite uses fake desktop/power APIs. No runner's lock, screensaver,
    // power policy, passwords or registry are changed by --test-suite.
    internal static class ScreenSaverTests
    {
        private sealed class Desktop : IScreenSaverPlatform, IMachineInactivityPlatform
        {
            internal bool Enabled = true, Managed, IgnoreWrite, ThrowAfterDisable, FailRestore;
            internal bool Elevated, MachineExists, FailMachineWrite, FailMachineRestore, CancelElevation;
            internal uint MachineSeconds;
            internal string Stamp = "profile-unchanged", UserId = "test-user", LogonId = "test-logon", LockWarning;
            internal int Writes, MachineWrites, MachineAttempts;
            internal readonly List<string> Trace = new List<string>();
            public string User { get { return UserId; } }
            public string Logon { get { return LogonId; } }
            public ScreenSaverState Read()
            {
                string warning = LockWarning;
                if (MachineExists && MachineSeconds > 0)
                {
                    string policy = "Windows machine inactivity policy requires lock after " + MachineSeconds
                        + " seconds. Run Windows No Sleep as administrator to temporarily disable it while Protection is active.";
                    warning = string.IsNullOrWhiteSpace(warning) ? policy : warning + " " + policy;
                }
                return new ScreenSaverState { Enabled = Enabled, Secure = true, Timeout = 60,
                    SettingsManaged = Managed, ProfileStamp = Stamp, LockWarning = warning };
            }
            public void SetActive(bool enabled)
            {
                if (enabled && FailRestore) throw new IOException("restore denied");
                Writes++; Trace.Add(enabled ? "enable" : "disable");
                if (!IgnoreWrite) Enabled = enabled;
                if (!enabled && ThrowAfterDisable) throw new IOException("interrupted after write");
            }
            public bool IsElevated { get { return Elevated; } }
            public MachineInactivityState ReadMachineInactivity()
            {
                return new MachineInactivityState { Exists = MachineExists, Seconds = MachineSeconds };
            }
            public void SetMachineInactivity(uint seconds)
            {
                MachineAttempts++;
                if (!Elevated && CancelElevation) throw new OperationCanceledException("Administrator approval was cancelled.");
                if (seconds == 0 && FailMachineWrite) throw new IOException("machine write failed");
                if (seconds != 0 && FailMachineRestore) throw new IOException("machine restore failed");
                MachineWrites++; Trace.Add("machine=" + seconds);
                MachineExists = true; MachineSeconds = seconds;
            }
        }
        private sealed class MachineStore : IMachineInactivityStore
        {
            internal MachineInactivityRecord Record;
            internal bool FailSave, FailClear;
            internal readonly List<string> Trace;
            internal MachineStore(List<string> trace) { Trace = trace; }
            public bool Exists { get { return Record != null; } }
            public MachineInactivityRecord Load() { return Record; }
            public void Save(MachineInactivityRecord record)
            {
                if (FailSave) throw new IOException("machine journal unavailable");
                record.Machine = "test-machine"; record.User = "test-user"; record.Validate();
                Trace.Add("machine-save"); Record = record;
            }
            public void Clear(MachineInactivityRecord record, string disposition)
            {
                if (FailClear) throw new IOException("machine receipt failed");
                Trace.Add("machine-clear"); Record = null;
            }
        }
        private sealed class Store : IScreenSaverStore
        {
            internal ScreenSaverRecord Record;
            internal bool FailSave, FailClear;
            internal readonly List<string> Trace;
            internal Store(List<string> trace) { Trace = trace; }
            public bool Exists { get { return Record != null; } }
            public ScreenSaverRecord Load() { return Record; }
            public void Save(ScreenSaverRecord record)
            {
                if (FailSave) throw new IOException("journal unavailable");
                Trace.Add("save"); Record = record;
            }
            public void Clear(ScreenSaverRecord record, string disposition)
            {
                if (FailClear) throw new IOException("receipt failed");
                Trace.Add("clear"); Record = null;
            }
        }
        private sealed class Rig
        {
            internal readonly Desktop Desktop = new Desktop();
            internal readonly Store Store;
            internal readonly MachineStore MachineStore;
            internal readonly ScreenSaverProtection Protection;
            internal Rig()
            {
                Store = new Store(Desktop.Trace); MachineStore = new MachineStore(Desktop.Trace); Protection = NewProtection();
            }
            internal ScreenSaverProtection NewProtection()
            {
                return new ScreenSaverProtection(Desktop, Store, delegate { }, Desktop, MachineStore);
            }
        }
        private sealed class Sensor : IPowerSensor
        {
            internal PowerSnapshot Value = new PowerSnapshot { ReadSucceeded = true, CapabilitiesKnown = true,
                HasBattery = true, OnAc = true, Percent = 80 };
            public PowerSnapshot ReadPower() { return Value; }
        }
        private sealed class PowerPolicy : IPowerPolicy
        {
            public Guid ActiveScheme() { return new Guid("381b4222-f694-41f0-9685-ff5bb260df2e"); }
            public uint Read(Guid scheme, string key) { return 0; }
            public void CheckWrite(string key) { throw new Exception("Unexpected real-policy lane in desktop tests"); }
            public void Write(Guid scheme, string key, uint value) { throw new Exception("Unexpected policy write"); }
            public void RefreshIfActive(Guid scheme) { }
        }
        private sealed class PowerStore : IRecoveryStore
        {
            internal bool FailRestore;
            public bool Exists { get { return FailRestore; } }
            public RecoveryJournal Load() { if (FailRestore) throw new IOException("power restore failed"); return null; }
            public void Save(RecoveryJournal record) { throw new Exception("Unexpected policy journal"); }
            public void Clear(RecoveryJournal record) { }
        }
        private sealed class Guard : IShutdownGuard
        {
            public bool IsArmed { get; private set; }
            public void Set(bool enabled) { IsArmed = enabled; }
        }
        private sealed class Lease : IDisposable
        {
            private Action _release;
            internal Lease(Action release) { _release = release; }
            public void Dispose() { if (_release != null) { _release(); _release = null; } }
        }
        private sealed class CoreRig
        {
            internal readonly Rig Desktop = new Rig();
            internal readonly Sensor Sensor = new Sensor();
            internal readonly PowerStore Store = new PowerStore();
            internal readonly Guard Guard = new Guard();
            internal readonly ProtectionController Core;
            internal int Leases;
            internal CoreRig(bool machinePolicy = false, bool elevated = false)
            {
                Desktop.Desktop.MachineExists = machinePolicy;
                Desktop.Desktop.MachineSeconds = machinePolicy ? 900u : 0u;
                Desktop.Desktop.Elevated = elevated;
                Core = new ProtectionController(new AppOptions { LidProtection = false, DcTimeoutProtection = false }, Sensor,
                    new PolicyTransaction(new PowerPolicy(), Store, delegate { }), Guard,
                    delegate { Leases++; return new Lease(delegate { Leases--; }); }, delegate { }, Desktop.Protection)
                    { PolicyRecoveryReady = true };
            }
        }
        internal static int Run(string report)
        {
            int total = 0, failed = 0;
            var output = new StringBuilder("\n# Screensaver / idle-lock regressions (FAKE desktop APIs)\n");
            Action<string, Action> test = delegate(string name, Action body)
            {
                total++;
                try { body(); output.AppendLine("PASS " + name); }
                catch (Exception error) { failed++; output.AppendLine("FAIL " + name + ": " + error); }
            };
            test("screensaver prevention enabled for new settings", delegate { Assert(new AppOptions().PreventScreenSaver != false); });
            test("idle-lock checkbox is indeterminate while admin approval is pending", delegate
            {
                Assert(SettingsForm.ScreenSaverCheckState(true, true) == System.Windows.Forms.CheckState.Indeterminate);
                Assert(SettingsForm.ScreenSaverCheckState(true, false) == System.Windows.Forms.CheckState.Checked);
                Assert(SettingsForm.ScreenSaverCheckState(false, true) == System.Windows.Forms.CheckState.Unchecked);
            });
            test("0.4 settings without field migrate to enabled", delegate
            {
                const string old = "{\"Version\":1,\"ProtectOnBattery\":true,\"LidProtection\":true,\"DcTimeoutProtection\":true,\"BlockShutdown\":true,\"BatterySafetyPercent\":15}";
                using (var stream = new MemoryStream(Encoding.UTF8.GetBytes(old)))
                {
                    var options = (AppOptions)new DataContractJsonSerializer(typeof(AppOptions)).ReadObject(stream);
                    options.Validate(); Assert(options.PreventScreenSaver != false);
                }
            });
            test("explicit disabled preference survives serialization", delegate
            {
                using (var stream = new MemoryStream())
                {
                    var serializer = new DataContractJsonSerializer(typeof(AppOptions));
                    serializer.WriteObject(stream, new AppOptions { PreventScreenSaver = false }); stream.Position = 0;
                    Assert(((AppOptions)serializer.ReadObject(stream)).PreventScreenSaver == false);
                }
            });
            test("write-ahead before disable and readback active", delegate
            {
                var r = new Rig(); r.Protection.Start(true);
                Assert(r.Protection.Active && !r.Desktop.Enabled && r.Store.Exists);
                Assert(r.Desktop.Trace.Take(2).SequenceEqual(new[] { "save", "disable" }));
                r.Protection.Restore(); Assert(r.Desktop.Enabled && !r.Store.Exists && !r.Protection.Active);
            });
            test("originally disabled screensaver never changed", delegate
            {
                var r = new Rig(); r.Desktop.Enabled = false; r.Protection.Start(true); r.Protection.Restore();
                Assert(!r.Desktop.Enabled && r.Desktop.Writes == 0 && !r.Store.Exists);
            });
            test("unchecked option has zero writes", delegate { var r = new Rig(); r.Protection.Start(false); Assert(r.Desktop.Writes == 0 && !r.Protection.Active); });
            test("journal failure prevents mutation", delegate { var r = new Rig(); r.Store.FailSave = true; r.Protection.Start(true); Assert(r.Desktop.Writes == 0 && !r.Protection.Active && r.Protection.Warning != null); });
            test("missing recovery registration prevents mutation", delegate { var r = new Rig(); r.Protection.RecoveryReady = false; r.Protection.Start(true); Assert(r.Desktop.Writes == 0 && r.Protection.Warning != null); });
            test("managed screensaver not overridden", delegate { var r = new Rig(); r.Desktop.Managed = true; r.Protection.Start(true); Assert(r.Desktop.Writes == 0 && !r.Protection.Active && r.Protection.Warning != null); });
            test("machine inactivity warning never hidden", delegate
            {
                var r = new Rig(); r.Desktop.LockWarning = "Windows requires lock after 60 seconds"; r.Protection.Start(true);
                Assert(r.Protection.Warning.Contains("60 seconds")); r.Protection.Restore();
            });
            test("non-admin main can use elevated machine helper", delegate
            {
                var r = new Rig(); r.Desktop.MachineExists = true; r.Desktop.MachineSeconds = 900; r.Protection.Start(true);
                Assert(r.Protection.Active && r.Desktop.MachineSeconds == 0 && r.Desktop.MachineWrites == 1
                    && r.Protection.Warning == null); r.Protection.Restore();
                Assert(r.Desktop.MachineSeconds == 900 && r.Desktop.MachineWrites == 2);
            });
            test("cancelled administrator approval is latched without UAC spam", delegate
            {
                var r = new Rig(); r.Desktop.MachineExists = true; r.Desktop.MachineSeconds = 900; r.Desktop.CancelElevation = true;
                r.Protection.Start(true);
                Assert(r.Protection.Active && r.Desktop.MachineSeconds == 900 && !r.MachineStore.Exists
                    && r.Protection.Warning.Contains("cancelled") && r.Desktop.MachineAttempts == 1);
                r.Protection.Poll();
                r.Protection.Start(true);
                Assert(r.Desktop.MachineAttempts == 1 && r.Desktop.MachineSeconds == 900);
                r.Protection.AllowAdministratorRetry();
                r.Protection.Start(true);
                Assert(r.Desktop.MachineAttempts == 2);
            });
            test("admin temporarily disables and restores local machine inactivity policy", delegate
            {
                var r = new Rig(); r.Desktop.MachineExists = true; r.Desktop.MachineSeconds = 900; r.Desktop.Elevated = true;
                r.Protection.Start(true);
                Assert(r.Desktop.MachineSeconds == 0 && r.MachineStore.Exists && r.Protection.Warning == null);
                Assert(r.Desktop.Trace.IndexOf("machine-save") < r.Desktop.Trace.IndexOf("machine=0"));
                r.Protection.Restore();
                Assert(r.Desktop.MachineSeconds == 900 && !r.MachineStore.Exists);
            });
            test("machine inactivity restore failure preserves durable record", delegate
            {
                var r = new Rig(); r.Desktop.MachineExists = true; r.Desktop.MachineSeconds = 900; r.Desktop.Elevated = true;
                r.Protection.Start(true); r.Desktop.FailMachineRestore = true; Throws(r.Protection.Restore);
                Assert(r.MachineStore.Exists && r.Desktop.MachineSeconds == 0);
                r.Desktop.FailMachineRestore = false; r.Protection.Restore(); Assert(!r.MachineStore.Exists && r.Desktop.MachineSeconds == 900);
            });
            test("external machine inactivity value is not overwritten", delegate
            {
                var r = new Rig(); r.Desktop.MachineExists = true; r.Desktop.MachineSeconds = 900; r.Desktop.Elevated = true;
                r.Protection.Start(true); r.Desktop.MachineSeconds = 600; Throws(r.Protection.Restore);
                Assert(r.MachineStore.Exists && r.Desktop.MachineSeconds == 600);
            });
            test("successor restores machine inactivity before applying a new session", delegate
            {
                var r = new Rig(); r.Desktop.MachineExists = true; r.Desktop.MachineSeconds = 900; r.Desktop.Elevated = true;
                r.Protection.Start(true); var successor = r.NewProtection(); successor.Start(true);
                Assert(r.Desktop.MachineSeconds == 0 && r.MachineStore.Exists); successor.Restore();
                Assert(r.Desktop.MachineSeconds == 900 && !r.MachineStore.Exists);
            });
            test("ignored Windows write cannot claim active", delegate { var r = new Rig(); r.Desktop.IgnoreWrite = true; r.Protection.Start(true); Assert(!r.Protection.Active && r.Protection.Warning != null && r.Desktop.Enabled); });
            test("failure after disable restores original", delegate { var r = new Rig(); r.Desktop.ThrowAfterDisable = true; r.Protection.Start(true); Assert(r.Desktop.Enabled && !r.Store.Exists && !r.Protection.Active); });
            test("restore failure preserves durable record", delegate { var r = new Rig(); r.Protection.Start(true); r.Desktop.FailRestore = true; Throws(r.Protection.Restore); Assert(r.Store.Exists); r.Desktop.FailRestore = false; r.Protection.Restore(); Assert(r.Desktop.Enabled && !r.Store.Exists); });
            test("restore receipt failure preserves record", delegate { var r = new Rig(); r.Protection.Start(true); r.Store.FailClear = true; Throws(r.Protection.Restore); Assert(r.Desktop.Enabled && r.Store.Exists); });
            test("crash before first API write safe on next launch", delegate
            {
                var r = new Rig(); r.Store.Record = Record(r); r.NewProtection().Restore();
                Assert(r.Desktop.Writes == 0 && r.Desktop.Enabled && !r.Store.Exists);
            });
            test("force-kill same-logon recovery before new protection", delegate
            {
                var r = new Rig(); r.Protection.Start(true); r.Desktop.Trace.Clear(); var successor = r.NewProtection(); successor.Start(true);
                Assert(r.Desktop.Trace.SequenceEqual(new[] { "enable", "clear", "save", "disable" })); successor.Restore();
            });
            test("new logon never replays old volatile override", delegate
            {
                var r = new Rig(); r.Protection.Start(true); r.Desktop.Enabled = true; r.Desktop.LogonId = "new-logon";
                int before = r.Desktop.Writes; r.NewProtection().Restore(); Assert(r.Desktop.Writes == before && !r.Store.Exists);
            });
            test("wrong account journal preserved without writes", delegate
            {
                var r = new Rig(); r.Store.Record = Record(r); r.Desktop.UserId = "different-account";
                Throws(r.Protection.Restore); Assert(r.Store.Exists && r.Desktop.Writes == 0);
            });
            test("invalid journal preserved without writes", delegate
            {
                var r = new Rig(); r.Store.Record = Record(r); r.Store.Record.Version = 999;
                Throws(r.Protection.Restore); Assert(r.Store.Exists && r.Desktop.Writes == 0);
            });
            test("external profile edit is not overwritten", delegate
            {
                var r = new Rig(); r.Protection.Start(true); r.Desktop.Stamp = "changed-profile"; int writes = r.Desktop.Writes;
                Throws(r.Protection.Restore); Assert(r.Store.Exists && r.Desktop.Writes == writes);
            });
            test("poll detects external re-enable without fighting it", delegate
            {
                var r = new Rig(); r.Protection.Start(true); r.Desktop.Enabled = true; int writes = r.Desktop.Writes; r.Protection.Poll();
                Assert(!r.Protection.Active && r.Protection.Warning != null && r.Desktop.Writes == writes && !r.Store.Exists);
            });
            test("new enforced policy is not repeatedly suppressed", delegate
            {
                var r = new Rig(); r.Protection.Start(true); r.Desktop.Managed = true; int writes = r.Desktop.Writes;
                r.Protection.Poll(); r.Protection.Poll(); Assert(r.Protection.Warning != null && r.Desktop.Writes == writes && r.Store.Exists);
            });
            test("unexpected/manual lock becomes visible not Protected claim", delegate
            {
                var r = new Rig(); r.Protection.Start(true); r.Protection.ObserveSessionLock(); r.Protection.Poll();
                Assert(r.Protection.Warning.Contains("Windows locked")); r.Protection.Restore();
            });
            test("controller starts default screensaver suppression", delegate { var r = new CoreRig(); r.Core.Start(); Assert(!r.Desktop.Desktop.Enabled && r.Core.State == ProtectionState.Protected); r.Core.Stop(); });
            test("controller Stop restores screensaver and releases awake", delegate { var r = new CoreRig(); r.Core.Start(); r.Core.Stop(); Assert(r.Desktop.Desktop.Enabled && r.Leases == 0 && !r.Core.RecoveryPending); });
            test("battery safety restores screensaver and releases blockers", delegate
            {
                var r = new CoreRig(); r.Core.Start(); r.Sensor.Value.OnAc = false; r.Sensor.Value.Percent = 15; r.Core.Poll();
                Assert(r.Core.State == ProtectionState.BatterySafety && r.Desktop.Desktop.Enabled && r.Leases == 0 && !r.Guard.IsArmed && !r.Core.RecoveryPending);
                r.Sensor.Value.OnAc = true; r.Core.Poll(); Assert(!r.Desktop.Desktop.Enabled && r.Leases == 1); r.Core.Stop();
            });
            test("suspend restores and resume reapplies screensaver", delegate { var r = new CoreRig(); r.Core.Start(); r.Core.Suspend(); Assert(r.Desktop.Desktop.Enabled); r.Core.Resume(); Assert(!r.Desktop.Desktop.Enabled); r.Core.Stop(); });
            test("toggle option restores before persistence", delegate
            {
                var r = new CoreRig(); r.Core.Start(); var options = r.Core.Options.Copy(); options.PreventScreenSaver = false;
                r.Core.ChangeOptions(options, delegate { Assert(r.Desktop.Desktop.Enabled && !r.Desktop.Store.Exists); });
                Assert(r.Desktop.Desktop.Enabled && r.Core.IsAwake); r.Core.Stop();
            });
            test("controller elevated local inactivity override is Protected", delegate
            {
                var r = new CoreRig(true, true); r.Core.Start();
                Assert(r.Core.State == ProtectionState.Protected && r.Desktop.Desktop.MachineSeconds == 0);
                r.Core.Stop(); Assert(r.Desktop.Desktop.MachineSeconds == 900);
            });
            test("controller non-admin main reaches Protected through helper", delegate
            {
                var r = new CoreRig(true, false); r.Core.Start();
                Assert(r.Core.State == ProtectionState.Protected && r.Desktop.Desktop.MachineSeconds == 0);
                r.Core.Stop(); Assert(r.Desktop.Desktop.MachineSeconds == 900);
            });
            test("controller cancelled admin approval stays Degraded without repeated prompt", delegate
            {
                var r = new CoreRig(true, false); r.Desktop.Desktop.CancelElevation = true; r.Core.Start();
                Assert(r.Core.State == ProtectionState.Degraded && r.Desktop.Desktop.MachineSeconds == 900
                    && !r.Desktop.MachineStore.Exists && r.Desktop.Desktop.MachineAttempts == 1);
                r.Core.Poll(); r.Core.Poll();
                Assert(r.Desktop.Desktop.MachineAttempts == 1);
                r.Core.Stop();
            });
            test("controller managed lock warning yields Degraded", delegate
            {
                var r = new CoreRig(); r.Desktop.Desktop.LockWarning = "machine inactivity policy"; r.Core.Start();
                Assert(r.Core.State == ProtectionState.Degraded && r.Core.Detail.Contains("machine inactivity")); r.Core.Stop();
            });
            test("live lock observation changes overall status", delegate
            {
                var r = new CoreRig(); r.Core.Start(); r.Desktop.Protection.ObserveSessionLock(); r.Core.Poll();
                Assert(r.Core.State == ProtectionState.Degraded && r.Core.Detail.Contains("Windows locked")); r.Core.Stop();
            });
            test("crash recovery includes screensaver", delegate
            {
                var r = new CoreRig(); r.Core.Start(); Assert(r.Core.RecoverForCrash(null));
                Assert(r.Desktop.Desktop.Enabled && !r.Desktop.Store.Exists && r.Leases == 0);
            });
            test("power recovery failure does not skip screensaver restore", delegate
            {
                var r = new CoreRig(); r.Core.Start(); r.Store.FailRestore = true; Assert(!r.Core.RecoverForCrash(null));
                Assert(r.Desktop.Desktop.Enabled && !r.Desktop.Store.Exists && r.Leases == 0);
            });
            test("screensaver recovery failure cannot hide behind Stopped", delegate
            {
                var r = new CoreRig(); r.Core.Start(); r.Desktop.Desktop.FailRestore = true; r.Core.Stop();
                Assert(r.Core.State == ProtectionState.Degraded && r.Core.RecoveryPending && r.Leases == 0);
            });
            test("disk journal roundtrip and restoration receipt", delegate
            {
                string path = Path.Combine(Path.GetTempPath(), "wns-desktop-test-" + Guid.NewGuid().ToString("N"));
                try
                {
                    var desktop = new Desktop(); var store = new ScreenSaverJournalStore(path);
                    var protection = new ScreenSaverProtection(desktop, store, delegate { });
                    protection.Start(true); Assert(store.Exists && !desktop.Enabled);
                    protection.Restore(); Assert(!store.Exists && desktop.Enabled && File.Exists(Path.Combine(path, "last-desktop-restore.json")));
                }
                finally { if (Directory.Exists(path)) Directory.Delete(path, true); }
            });
            output.AppendLine("SCREENSAVER_TOTAL=" + total + " PASSED=" + (total - failed) + " FAILED=" + failed);
            try { File.AppendAllText(Path.GetFullPath(report), output.ToString(), Encoding.UTF8); }
            catch { return 2; }
            return failed == 0 ? 0 : 1;
        }
        private static ScreenSaverRecord Record(Rig rig)
        {
            return new ScreenSaverRecord { User = rig.Desktop.User, Logon = rig.Desktop.Logon,
                OriginalActive = true, ProfileStamp = rig.Desktop.Stamp };
        }
        private static void Assert(bool value) { if (!value) throw new Exception("Assertion failed"); }
        private static void Throws(Action body)
        {
            bool thrown = false;
            try { body(); } catch { thrown = true; }
            Assert(thrown);
        }
    }
}
