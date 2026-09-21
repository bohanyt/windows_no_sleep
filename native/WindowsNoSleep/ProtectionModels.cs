using System;
using System.Collections.Generic;
using System.Runtime.Serialization;

namespace WindowsNoSleep
{
    [DataContract]
    internal sealed class AppOptions
    {
        [DataMember(IsRequired = true)] public int Version = 1;
        [DataMember(IsRequired = true)] public bool ProtectOnBattery = true;
        [DataMember(IsRequired = true)] public bool LidProtection = true;
        [DataMember(IsRequired = true)] public bool DcTimeoutProtection = true;
        [DataMember(IsRequired = true)] public bool BlockShutdown = true;
        [DataMember(IsRequired = true)] public int BatterySafetyPercent = 15;
        internal void Validate()
        {
            if (Version != 1 || BatterySafetyPercent < 15 || BatterySafetyPercent > 95)
                throw new InvalidOperationException("Unsupported or invalid settings.");
        }
        internal AppOptions Copy() { return (AppOptions)MemberwiseClone(); }
    }

    internal sealed class PowerSnapshot
    {
        internal bool ReadSucceeded, CapabilitiesKnown, HasBattery, LidPresent, HibernateAvailable, ModernStandby, Critical;
        internal bool? OnAc;
        internal int? Percent, CriticalThreshold;
    }
    internal static class BatteryRules
    {
        internal static int Threshold(int requested, int? critical)
        {
            int threshold = Math.Max(15, Math.Min(95, requested));
            if (critical.HasValue && critical.Value >= 0 && critical.Value <= 100)
                threshold = Math.Max(threshold, Math.Min(100, critical.Value + 5));
            return threshold;
        }
        internal static bool MustPause(PowerSnapshot power, int threshold, bool wasPaused)
        {
            if (power == null || !power.ReadSucceeded) return true;
            if (power.OnAc == true) return false;
            if (!power.HasBattery) return false;
            if (!power.OnAc.HasValue || !power.Percent.HasValue || power.Percent < 0 || power.Percent > 100 || power.Critical) return true;
            return power.Percent.Value <= threshold || (wasPaused && power.Percent.Value < Math.Min(100, threshold + 5));
        }
    }
    internal interface IPowerSensor { PowerSnapshot ReadPower(); }
    internal interface IPowerPolicy
    {
        Guid ActiveScheme();
        uint Read(Guid scheme, string key);
        void CheckWrite(string key);
        void Write(Guid scheme, string key, uint value);
        void RefreshIfActive(Guid scheme);
    }
    internal interface IShutdownGuard
    {
        bool IsArmed { get; }
        void Set(bool enabled);
    }
    internal interface IRecoveryStore
    {
        bool Exists { get; }
        RecoveryJournal Load();
        void Save(RecoveryJournal journal);
        void Clear(RecoveryJournal verifiedJournal);
    }
    [DataContract]
    internal sealed class RecoveryJournal
    {
        [DataMember(IsRequired = true)] public int Version = 1;
        [DataMember(IsRequired = true)] public string Product = "WindowsNoSleep.Native";
        [DataMember(IsRequired = true)] public string Transaction = Guid.NewGuid().ToString("D");
        [DataMember(IsRequired = true)] public string Machine;
        [DataMember(IsRequired = true)] public string User;
        [DataMember(IsRequired = true)] public string Scheme;
        [DataMember(IsRequired = true)] public string CreatedUtc = DateTime.UtcNow.ToString("o");
        [DataMember(IsRequired = true)] public List<RecoveryEntry> Entries = new List<RecoveryEntry>();
        internal void Validate()
        {
            Guid parsed;
            if (Version != 1 || Product != "WindowsNoSleep.Native" || !Guid.TryParse(Transaction, out parsed)
                || !Guid.TryParse(Scheme, out parsed) || parsed == Guid.Empty || Entries == null || Entries.Count > 4)
                throw new InvalidOperationException("Recovery journal is invalid or from another app. It has been preserved.");
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var entry in Entries)
            {
                if (entry == null || !PolicyKeys.IsAllowed(entry.Key) || !names.Add(entry.Key) || entry.Applied != 0
                    || ((entry.Key == PolicyKeys.LidAc || entry.Key == PolicyKeys.LidDc) && entry.Original > 3))
                    throw new InvalidOperationException("Recovery journal contains an invalid setting. No recovery writes were attempted.");
            }
        }
    }
    [DataContract]
    internal sealed class RecoveryEntry
    {
        [DataMember(IsRequired = true)] public string Key;
        [DataMember(IsRequired = true)] public uint Original;
        [DataMember(IsRequired = true)] public uint Applied;
        [DataMember(IsRequired = true)] public bool Attempted;
    }
    internal enum ProtectionState { Starting, Protected, Stopped, BatterySafety, Degraded, Suspended }
}
