using System;
using System.Collections.Generic;
using System.Linq;

namespace WindowsNoSleep
{
    // No OS mutation precedes a durable snapshot. The controller serializes calls;
    // _applying also guards same-thread Win32 message re-entrancy during refresh.
    internal sealed class PolicyTransaction
    {
        private readonly IPowerPolicy _policy;
        private readonly IRecoveryStore _store;
        private readonly Action<string> _log;
        private Guid _scheme;
        private bool _applying;
        private IList<string> _monitored = new List<string>();
        internal bool Active { get; private set; }
        internal bool Pending { get { return _store.Exists; } }
        internal PolicyTransaction(IPowerPolicy policy, IRecoveryStore store, Action<string> log)
        {
            _policy = policy; _store = store; _log = log;
        }
        internal void Apply(IList<string> keys, Func<bool> shouldContinue = null)
        {
            if (Active) return;
            if (_applying) throw new InvalidOperationException("A power transaction is already in progress.");
            if (_store.Exists) throw new InvalidOperationException("Previous recovery must complete before a new protection session.");
            if (keys.Count == 0) return;
            _applying = true;
            try
            {
                _scheme = _policy.ActiveScheme();
                var journal = new RecoveryJournal { Scheme = _scheme.ToString("D") };
                foreach (string key in keys)
                {
                    if (!PolicyKeys.IsAllowed(key)) throw new InvalidOperationException("Unapproved power setting.");
                    uint original = _policy.Read(_scheme, key);
                    if ((key == PolicyKeys.LidAc || key == PolicyKeys.LidDc) && original > 3)
                        throw new InvalidOperationException("Unknown lid action; policy was not changed.");
                    if (original != 0)
                    {
                        _policy.CheckWrite(key);
                        journal.Entries.Add(new RecoveryEntry { Key = key, Original = original, Applied = 0 });
                    }
                }
                journal.Validate();
                RequireSameScheme(); RequireContinue(shouldContinue);
                if (journal.Entries.Count != 0) _store.Save(journal);
                foreach (RecoveryEntry entry in journal.Entries)
                {
                    RequireSameScheme(); RequireContinue(shouldContinue);
                    if (_policy.Read(_scheme, entry.Key) != entry.Original)
                        throw new InvalidOperationException("Power setting changed during startup: " + entry.Key);
                    entry.Attempted = true;
                    _store.Save(journal); // A crash even inside Write() leaves recovery evidence.
                    RequireContinue(shouldContinue);
                    _log("POLICY_BEFORE " + entry.Key + " original=" + entry.Original + " temporary=0 scheme=" + journal.Scheme);
                    _policy.Write(_scheme, entry.Key, entry.Applied);
                    if (_policy.Read(_scheme, entry.Key) != entry.Applied)
                        throw new InvalidOperationException("Power setting write was not verified: " + entry.Key);
                    RequireContinue(shouldContinue);
                }
                if (journal.Entries.Count != 0) _policy.RefreshIfActive(_scheme);
                RequireSameScheme(); RequireContinue(shouldContinue);
                foreach (string key in keys)
                    if (_policy.Read(_scheme, key) != 0) throw new InvalidOperationException("Power setting changed during apply: " + key);
                _monitored = new List<string>(keys);
                Active = true;
                _log("POLICY_ACTIVE scheme=" + _scheme + " changed=" + journal.Entries.Count);
            }
            catch (Exception applyError)
            {
                _applying = false;
                try { Restore(); }
                catch (Exception restoreError)
                {
                    throw new InvalidOperationException(applyError.Message + " Restore pending: " + restoreError.Message, applyError);
                }
                throw;
            }
            finally { _applying = false; }
        }
        private static void RequireContinue(Func<bool> shouldContinue)
        {
            if (shouldContinue != null && !shouldContinue())
                throw new OperationCanceledException("Protection stopped during startup; temporary values will be restored.");
        }
        internal bool HasDrift()
        {
            if (!Active) return false;
            return _policy.ActiveScheme() != _scheme || _monitored.Any(key => _policy.Read(_scheme, key) != 0);
        }
        private void RequireSameScheme()
        {
            if (_policy.ActiveScheme() != _scheme) throw new InvalidOperationException("Active power plan changed; no new plan will be selected.");
        }
        internal void Restore(Action pulse = null)
        {
            if (_applying) throw new InvalidOperationException("Power transaction is finishing; its recovery journal is preserved.");
            Active = false;
            _monitored = new List<string>();
            RecoveryJournal journal = _store.Load();
            if (journal == null) return;
            journal.Validate();
            Guid scheme = new Guid(journal.Scheme);
            var errors = new List<string>();
            foreach (RecoveryEntry entry in journal.Entries.Where(entry => entry.Attempted))
            {
                if (pulse != null) pulse(); // WER cancellation must stop promptly, without clearing the journal.
                try
                {
                    uint current = _policy.Read(scheme, entry.Key);
                    // Preserve external changes rather than overwriting them with stale originals.
                    if (current != entry.Original && current != entry.Applied)
                        throw new InvalidOperationException("Conflicting external value for " + entry.Key + "; recovery record preserved.");
                    if (current != entry.Original) _policy.Write(scheme, entry.Key, entry.Original);
                    if (_policy.Read(scheme, entry.Key) != entry.Original)
                        throw new InvalidOperationException("Restore verification failed for " + entry.Key);
                    _log("RESTORE_VALUE " + entry.Key + " original=" + entry.Original + " after=" + entry.Original + " scheme=" + scheme);
                }
                catch (Exception error) { errors.Add(error.Message); }
            }
            try
            {
                if (journal.Entries.Any(entry => entry.Attempted)) _policy.RefreshIfActive(scheme);
                foreach (RecoveryEntry entry in journal.Entries.Where(entry => entry.Attempted))
                    if (_policy.Read(scheme, entry.Key) != entry.Original) errors.Add("Final read-back differs: " + entry.Key);
            }
            catch (Exception error) { errors.Add(error.Message); }
            if (errors.Count != 0) throw new InvalidOperationException(string.Join("; ", errors));
            _store.Clear(journal);
            _log("RESTORE_VERIFIED transaction=" + journal.Transaction + " scheme=" + scheme);
        }
    }
}
