namespace QuietHours.Windows
{
    /// Pure helpers for the Windows time format (unit-tested in windows/tests).
    static class TimeFormat
    {
        /// Windows short-time pattern → 24-hour? "H"/"HH" is the 24-hour hour, "h"/"hh" the 12-hour
        /// one; text in single quotes is literal ("HH 'h' mm" is 24-hour, "h 'H' mm" is not).
        public static bool IsTwentyFourHour(string pattern)
        {
            if (pattern == null) return false;
            bool quoted = false;
            foreach (char c in pattern)
            {
                if (c == '\'') quoted = !quoted;
                else if (!quoted && c == 'H') return true;
                else if (!quoted && c == 'h') return false;
            }
            return false;
        }
    }
}
