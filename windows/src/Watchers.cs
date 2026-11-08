using System;
using System.Windows.Forms;
using Microsoft.Win32;

namespace QuietHours.Windows
{
    /// Ends the full-screen saver on keyboard or mouse input, whichever window or process has
    /// focus. The page reports input too (keys, buttons, wheel, touch); this is the backstop:
    ///   - the cursor ends up more than a few pixels from where it settled;
    ///   - a key or mouse button is pressed (GetLastInputInfo advanced and a key state is set).
    /// Mouse jitter alone advances GetLastInputInfo too, but neither moves the cursor far nor
    /// sets a key state, so it never ends the saver.
    sealed class InputWatcher : IDisposable
    {
        const int MoveThreshold = 12;   // physical pixels: ignores a nudged desk or a noisy sensor
        // Swallows whatever started the saver: the mouse-up of Settings' Preview button, a key
        // release, the cursor settling.
        static readonly TimeSpan Grace = TimeSpan.FromMilliseconds(750);

        readonly Timer timer = new Timer { Interval = 50 };
        readonly Action exit;
        readonly DateTime started = DateTime.UtcNow;
        readonly bool[] held = new bool[256];
        Native.POINT origin;
        uint lastInput;

        public InputWatcher(Action exit)
        {
            this.exit = exit;
            Native.GetCursorPos(out origin);
            lastInput = Native.LastInputTick();
            Native.AnyKeyOrButtonPressed(held, record: true);   // also clears the "pressed since" bits
            timer.Tick += Check;
            timer.Start();
        }

        void Check(object sender, EventArgs e)
        {
            Native.GetCursorPos(out var p);
            uint input = Native.LastInputTick();

            if (DateTime.UtcNow - started < Grace)
            {
                origin = p;            // the new baseline
                lastInput = input;
                Native.AnyKeyOrButtonPressed(held, record: true);
                return;
            }
            if (Math.Abs(p.X - origin.X) > MoveThreshold || Math.Abs(p.Y - origin.Y) > MoveThreshold)
            {
                Fire();
                return;
            }
            if (input != lastInput)
            {
                lastInput = input;
                if (Native.AnyKeyOrButtonPressed(held)) Fire();
            }
        }

        void Fire()
        {
            timer.Stop();
            exit();
        }

        public void Dispose() => timer.Dispose();
    }

    /// Follows the Windows app theme and time format while the saver runs
    /// (WM_SETTINGCHANGE "ImmersiveColorSet" arrives as UserPreferenceChanged/General, "intl" as Locale).
    static class SystemWatcher
    {
        static Timer recheck;

        public static void Start() => SystemEvents.UserPreferenceChanged += OnChanged;

        public static void Stop()
        {
            SystemEvents.UserPreferenceChanged -= OnChanged;
            recheck?.Dispose();
            recheck = null;
        }

        static void OnChanged(object sender, UserPreferenceChangedEventArgs e)
        {
            if (e.Category != UserPreferenceCategory.General && e.Category != UserPreferenceCategory.Locale
                && e.Category != UserPreferenceCategory.Color && e.Category != UserPreferenceCategory.VisualStyle)
                return;
            Push();
            // The registry value can land a moment after the broadcast (the macOS build re-reads after 0.5 s too).
            recheck?.Dispose();
            recheck = new Timer { Interval = 600 };
            recheck.Tick += (s, a) => { recheck.Stop(); Push(); };
            recheck.Start();
        }

        static void Push()
        {
            foreach (var f in SaverForm.Open.ToArray())
                if (!f.IsDisposed) f.PushSystemPrefs();
        }
    }

    /// Displays added, removed or resized while the saver runs. DisplayPort monitors vanish
    /// when they sleep and come back on wake, so this matters even without docking.
    static class DisplayWatcher
    {
        static Action onChange;
        static Timer settle;

        public static void Start(Action action)
        {
            onChange = action;
            SystemEvents.DisplaySettingsChanged += OnChanged;
        }

        public static void Stop()
        {
            SystemEvents.DisplaySettingsChanged -= OnChanged;
            settle?.Dispose();
            settle = null;
        }

        static void OnChanged(object sender, EventArgs e)
        {
            // Several changes usually arrive together; act once they settle.
            settle?.Dispose();
            settle = new Timer { Interval = 500 };
            settle.Tick += (s, a) =>
            {
                settle.Stop();
                try { onChange?.Invoke(); }
                catch (Exception ex) { Log.Error("Displays", ex); }
            };
            settle.Start();
        }
    }
}
