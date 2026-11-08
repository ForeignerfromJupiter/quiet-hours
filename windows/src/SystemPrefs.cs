using System;
using System.Text;
using Microsoft.Win32;

namespace QuietHours.Windows
{
    /// Windows' light/dark mode and 12/24-hour setting, read live (no caching) so a change while
    /// the saver runs is picked up.
    static class SystemPrefs
    {
        /// Settings → Personalization → Colors → "Choose your app mode". 0 = dark; missing = light
        /// (the Windows default).
        public static bool IsDarkMode()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
                }
            }
            catch (Exception e)
            {
                Log.Error("IsDarkMode", e);
                return false;
            }
        }

        /// The user's short time format (Settings → Time & language → Region, or Control Panel →
        /// Region): "HH:mm" is 24-hour, "h:mm tt" is 12-hour. Read through GetLocaleInfoEx rather
        /// than CultureInfo, which caches it per thread.
        public static bool Uses24HourClock()
        {
            try
            {
                var buffer = new StringBuilder(80);
                if (Native.GetLocaleInfoEx(null, Native.LOCALE_SSHORTTIME, buffer, buffer.Capacity) > 0)
                    return TimeFormat.IsTwentyFourHour(buffer.ToString());
            }
            catch (Exception e)
            {
                Log.Error("Uses24HourClock", e);
            }
            return TimeFormat.IsTwentyFourHour(System.Globalization.CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern);
        }
    }
}
