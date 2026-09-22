using System;
using System.Collections.Generic;
using System.Threading;

namespace WindowsNoSleep
{
    internal sealed class ProtectionController
    {
        private readonly object _sync = new object();
        private readonly IPowerSensor _sensor;
        private readonly PolicyTransaction _transaction;
        private readonly IShutdownGuard _guard;
        private readonly Func<IDisposable> _acquireAwake;
        private readonly Action<string> _log;
        private readonly IScreenSaverProtection _screenSaver;
        private IDisposable _awake;
        private bool _wanted, _batteryPaused, _suspended, _faulted;
        private volatile bool _terminal;
        private ProtectionState _steadyState;
        private string _steadyDetail;
        internal bool PolicyRecoveryReady;
        internal string PolicyRecoveryError;
        internal AppOptions Options { get; private set; }
        internal PowerSnapshot Power { get; private set; }
        internal ProtectionState State { get; private set; }
        internal string Detail { get; private set; }
        internal string PolicyDetail { get; private set; }
        internal string ScreenSaverDetail { get { return _screenSaver == null ? "Not available" : _screenSaver.Detail; } }
        internal string ScreenSaverWarning { get { return _screenSaver == null ? null : _screenSaver.Warning; } }
        internal int EffectiveThreshold { get; private set; }
        internal bool IsAwake { get { return _awake != null; } }
        internal bool Wanted { get { return _wanted; } }
        internal bool GuardActive { get { return _guard.IsArmed; } }
        internal bool RecoveryPending
        {
            get { try { return _transaction.Pending || (_screenSaver != null && _screenSaver.Pending); } catch { return true; } }
        }
        internal ProtectionController(AppOptions options, IPowerSensor sensor, PolicyTransaction transaction,
            IShutdownGuard guard, Func<IDisposable> acquireAwake, Action<string> log, IScreenSaverProtection screenSaver = null)
        {
            options.Validate(); Options = options.Copy(); _sensor = sensor; _transaction = transaction;
            _guard = guard; _acquireAwake = acquireAwake; _log = log; _screenSaver = screenSaver;
            State = ProtectionState.Starting; Detail = "Starting protection..."; PolicyDetail = "Not applied";
            EffectiveThreshold = options.BatterySafetyPercent;
        }
        internal void Start()
        {
            lock (_sync)
            {
                if (_terminal) return;
                if (_wanted && _awake != null) return;
                _wanted = true; _faulted = false;
                try { RestoreSettings(null); }
                catch (Exception error)
                {
                    _faulted = true;
                    SetState(ProtectionState.Degraded, "Recovery needs attention; protection was not started. " + error.Message);
                    return;
                }
                EvaluateLocked();
            }
        }
        internal void Poll()
        {
            lock (_sync) { if (!_terminal) EvaluateLocked(); }
        }
        private void EvaluateLocked()
        {
            try { Power = _sensor.ReadPower(); }
            catch { Power = new PowerSnapshot(); }
            EffectiveThreshold = BatteryRules.Threshold(Options.BatterySafetyPercent, Power.CriticalThreshold);
            if (!_wanted || _suspended) return;
            bool unsafeBattery = BatteryRules.MustPause(Power, EffectiveThreshold, _batteryPaused);
            bool batteryDisabled = Power.HasBattery && Power.OnAc != true && !Options.ProtectOnBattery;
            if (unsafeBattery || batteryDisabled)
            {
                if (_awake != null || _guard.IsArmed || _transaction.Active || (_screenSaver != null && _screenSaver.Active))
                {
                    string cleanup = ReleaseOwned();
                    if (cleanup != null) { _faulted = true; PolicyDetail = "Restore pending: " + cleanup; }
                }
                _batteryPaused = unsafeBattery;
                SetState(unsafeBattery ? ProtectionState.BatterySafety : ProtectionState.Stopped,
                    unsafeBattery ? "Battery Safety - screensaver, sleep and shutdown are allowed. Protection resumes when power is safe."
                    : "Paused on battery - protection resumes when plugged in.");
                return;
            }
            _batteryPaused = false;
            if (_faulted)
            {
                SetState(ProtectionState.Degraded, "Protection is paused. Resolve the recovery error, then choose Start Protection.");
                return;
            }
            if (_awake != null)
            {
                try
                {
                    if (_transaction.HasDrift()) throw new InvalidOperationException("Windows power settings changed outside this app.");
                    if (_screenSaver != null) _screenSaver.Poll();
                    ApplyDesktopStatus();
                }
                catch (Exception error)
                {
                    string cleanup = ReleaseOwned();
                    _wanted = false; _faulted = true;
                    SetState(ProtectionState.Degraded, error.Message + " Protection stopped rather than overriding that change. " + cleanup);
                }
                return;
            }
            Activate();
        }
        private void Activate()
        {
            var warnings = new List<string>();
            try
            {
                _awake = _acquireAwake();
                if (_awake == null) throw new InvalidOperationException("Windows did not create an awake request.");
                if (_screenSaver != null) _screenSaver.Start(Options.PreventScreenSaver != false);
                try { _guard.Set(Options.BlockShutdown); }
                catch (Exception error) { warnings.Add("Restart guard unavailable: " + error.Message); }
                var keys = PolicyKeys.Requested(Options, Power);
                if (!Power.CapabilitiesKnown && (Options.LidProtection || Options.DcTimeoutProtection))
                    warnings.Add("Some power capabilities could not be detected.");
                PolicyDetail = keys.Count == 0 ? "Not needed for the selected options/hardware" : "Not applied";
                if (keys.Count != 0)
                {
                    if (!PolicyRecoveryReady)
                    {
                        PolicyDetail = "Unavailable: " + PolicyRecoveryError;
                        warnings.Add("Lid/DC overrides unavailable: " + PolicyRecoveryError);
                    }
                    else
                    {
                        try
                        {
                            _transaction.Apply(keys, delegate { return _wanted && !_suspended && !_terminal; });
                            PolicyDetail = "Lid/DC values verified; originals retained for restoration";
                        }
                        catch (Exception error)
                        {
                            PolicyDetail = "Unavailable: " + error.Message;
                            warnings.Add(PolicyDetail);
                            if (_transaction.Pending || !_wanted || _suspended || _terminal)
                                throw new InvalidOperationException("Startup interrupted or recovery pending: " + error.Message);
                        }
                    }
                }
                _steadyState = warnings.Count == 0 ? ProtectionState.Protected : ProtectionState.Degraded;
                _steadyDetail = warnings.Count == 0 ? "Awake protection active. See screensaver / idle-lock status below."
                    : "Basic awake request active. " + string.Join(" ", warnings);
                ApplyDesktopStatus();
            }
            catch (Exception error)
            {
                string cleanup = ReleaseOwned();
                _faulted = true;
                SetState(ProtectionState.Degraded, "Protection could not start safely. " + error.Message + " " + cleanup);
            }
        }
        private void ApplyDesktopStatus()
        {
            string warning = Options.PreventScreenSaver == false ? null : ScreenSaverWarning;
            SetState(warning == null ? _steadyState : ProtectionState.Degraded,
                _steadyDetail + (warning == null ? "" : " Screensaver / idle lock: " + warning));
        }
        private void RestoreSettings(Action pulse)
        {
            var errors = new List<string>();
            // Each recovery domain must be attempted even if the other one fails.
            try { if (_screenSaver != null) _screenSaver.Restore(); }
            catch (Exception error) { errors.Add("Screensaver: " + error.Message); }
            try
            {
                if (_transaction.Pending && !PolicyRecoveryReady)
                    throw new InvalidOperationException("Pending power recovery cannot run: " + PolicyRecoveryError);
                _transaction.Restore(pulse);
                PolicyDetail = "Original settings restored and verified (or no changes needed)";
            }
            catch (Exception error) { errors.Add(error.Message); PolicyDetail = "Restore pending: " + error.Message; }
            if (errors.Count != 0) throw new InvalidOperationException(string.Join("; ", errors));
        }
        private string ReleaseOwned()
        {
            var errors = new List<string>();
            try { _guard.Set(false); } catch (Exception error) { errors.Add(error.Message); }
            try { if (_awake != null) _awake.Dispose(); }
            catch (Exception error) { errors.Add(error.Message); }
            finally { _awake = null; }
            try { RestoreSettings(null); }
            catch (Exception error) { errors.Add(error.Message); }
            return errors.Count == 0 ? null : string.Join("; ", errors);
        }
        internal void Stop()
        {
            lock (_sync)
            {
                _wanted = false; _batteryPaused = false;
                string error = ReleaseOwned();
                if (_screenSaver != null) _screenSaver.AllowAdministratorRetry();
                _faulted = error != null;
                SetState(error == null ? ProtectionState.Stopped : ProtectionState.Degraded,
                    error == null ? "Protection stopped - Windows screensaver and sleep settings restored." : "Protection stopped; restore needs attention. " + error);
            }
        }
        internal void ChangeOptions(AppOptions options, Action<AppOptions> persist)
        {
            lock (_sync)
            {
                options.Validate(); bool resume = _wanted;
                Stop();
                if (_faulted) throw new InvalidOperationException("Restore the pending settings before changing protection options.");
                persist(options);
                Options = options.Copy();
                if (resume) Start();
            }
        }
        internal void Suspend()
        {
            lock (_sync)
            {
                _suspended = true;
                string error = ReleaseOwned();
                if (error != null) _faulted = true;
                SetState(ProtectionState.Suspended, "Windows is entering sleep; protection will be re-evaluated on resume. " + error);
            }
        }
        internal void Resume()
        {
            lock (_sync)
            {
                _suspended = false;
                if (_awake != null || _transaction.Active || (_screenSaver != null && _screenSaver.Active))
                {
                    string error = ReleaseOwned();
                    if (error != null) _faulted = true;
                }
                EvaluateLocked();
            }
        }
        internal bool MayBlockShutdown()
        {
            if (_terminal || !_wanted || _suspended || _awake == null || !_guard.IsArmed) return false;
            try
            {
                var fresh = _sensor.ReadPower();
                int threshold = BatteryRules.Threshold(Options.BatterySafetyPercent, fresh.CriticalThreshold);
                return !BatteryRules.MustPause(fresh, threshold, _batteryPaused)
                    && (Options.ProtectOnBattery || fresh.OnAc == true || !fresh.HasBattery);
            }
            catch { return false; }
        }
        internal bool RecoverForCrash(Action pulse)
        {
            _terminal = true;
            if (!Monitor.TryEnter(_sync, 100)) return false;
            try
            {
                bool success = true;
                try { if (_awake != null) _awake.Dispose(); } catch { success = false; }
                finally { _awake = null; }
                try { RestoreSettings(pulse); } catch { success = false; }
                return success;
            }
            finally { Monitor.Exit(_sync); }
        }
        private void SetState(ProtectionState state, string detail)
        {
            if (State != state || Detail != detail) _log("STATE " + state + " " + detail);
            State = state; Detail = detail;
        }
    }
}
