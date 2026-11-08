using System;
using System.Collections.Generic;
using System.Windows.Forms;
using Microsoft.Win32;

namespace QuietHours.Windows
{
    /// Ends the full-screen saver on keyboard, mouse or touch input, whichever window (or the
    /// WebView2 child process) has focus. The page reports input too; this is the backstop.
    ///   - the cursor moving more than a few pixels from where it started;
    ///   - any other input (keys, buttons, wheel): GetLastInputInfo advances while the cursor
    ///     stays put.
    sealed class InputWatcher : IDisposable
    {
        const int MoveThreshold = 12;          // physical pixels, ignores a nudge of the desk
        static readonly TimeSpan Grace = TimeSpan.FromMilliseconds(600);   // e.g. the Preview click's mouse-up

        readonly Timer timer = new Timer { Interval = 50 };
        readonly Action exit;
        readonly DateTime started = DateTime.UtcNow;
        Native.POINT origin, previous;
        uint lastInput;

        public InputWatcher(Action exit)
        {
            this.exit = exit;
            Native.GetCursorPos(out origin);
            previous = origin;
            lastInput = Native.LastInputTick();
            timer.Tick += Check;
            timer.Start();
        }

        void Check(object sender, EventArgs e)
        {
            Native.GetCursorPos(out var p);
            uint input = Native.LastInputTick();
            bool settled = DateTime.UtcNow - started > Grace;

            if (!settled)
            {
                origin = p;        // whatever happened during the grace period is the new baseline
                lastInput = input;
            }
            else if (Math.Abs(p.X - origin.X) > MoveThreshold || Math.Abs(p.Y - origin.Y) > MoveThreshold)
            {
                Fire();
                return;
            }
            else if (input != lastInput)
            {
                lastInput = input;
                if (p.X == previous.X && p.Y == previous.Y) { Fire(); return; }
            }
            previous = p;
        }

        void Fire()
        {
            timer.Stop();
            exit();
        }

        public void Dispose() => timer.Dispose();
    }

    /// Follows the Windows app theme and time format while the saver runs
    /// (WM_SETTINGCHANGE "ImmersiveColorSet" arrives as UserPreferenceChanged/General).
    static class SystemWatcher
    {
        static IReadOnlyList<SaverForm> forms;
        static Timer recheck;

        public static void Start(IReadOnlyList<SaverForm> list)
        {
            forms = list;
            SystemEvents.UserPreferenceChanged += OnChanged;
        }

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
            foreach (var f in forms)
                if (!f.IsDisposed) f.PushSystemPrefs();
        }
    }
}
