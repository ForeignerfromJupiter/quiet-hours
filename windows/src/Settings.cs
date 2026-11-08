using System;
using Microsoft.Win32;

namespace QuietHours.Windows
{
    enum Finish { Auto, Dark, Light }
    enum HourCycle { System, H12, H24 }

    /// Per-style options in HKCU\Software\Quiet Hours\<Style>, so the eight savers never share
    /// settings (like the per-bundle defaults on macOS). Re-read on every launch.
    sealed class Settings
    {
        public Finish Finish = Finish.Auto;
        public HourCycle HourCycle = HourCycle.System;
        public bool ShowSeconds;
        /// Dark finishes use a #000 room (OLED pixels off). On by default.
        public bool PureBlack = true;

        static string KeyPath(StyleInfo style) => @"Software\Quiet Hours\" + style.Name;

        public static Settings Load(StyleInfo style)
        {
            var s = new Settings();
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(KeyPath(style)))
                {
                    if (key == null) return s;
                    s.Finish = Parse(key.GetValue("Finish") as string, Finish.Auto);
                    s.HourCycle = Parse(key.GetValue("HourCycle") as string, HourCycle.System);
                    s.ShowSeconds = (key.GetValue("ShowSeconds") as int? ?? 0) != 0;
                    s.PureBlack = (key.GetValue("PureBlack") as int? ?? 1) != 0;
                }
            }
            catch (Exception e)
            {
                Log.Error("Settings.Load", e);
            }
            return s;
        }

        public void Save(StyleInfo style)
        {
            using (var key = Registry.CurrentUser.CreateSubKey(KeyPath(style)))
            {
                key.SetValue("Finish", Finish.ToString(), RegistryValueKind.String);
                key.SetValue("HourCycle", HourCycle.ToString(), RegistryValueKind.String);
                key.SetValue("ShowSeconds", ShowSeconds ? 1 : 0, RegistryValueKind.DWord);
                key.SetValue("PureBlack", PureBlack ? 1 : 0, RegistryValueKind.DWord);
            }
        }

        public bool Uses24Hour() =>
            HourCycle == HourCycle.H24 || (HourCycle == HourCycle.System && SystemPrefs.Uses24HourClock());

        static T Parse<T>(string raw, T fallback) where T : struct =>
            raw != null && Enum.TryParse(raw, true, out T v) ? v : fallback;
    }
}
