using System;
using System.Globalization;

namespace QuietHours.Windows
{
    enum LaunchMode { FullScreen, Preview, Configure, Window }

    /// Screen saver command line. Windows is loose about it: "/s", "/S", "-s", "/p 1234",
    /// "/p:1234", "/c:1234", "/c", or nothing at all (which means configure).
    struct LaunchArgs
    {
        public LaunchMode Mode;
        public IntPtr Window;

        public static LaunchArgs Parse(string[] args)
        {
            var result = new LaunchArgs { Mode = LaunchMode.Configure, Window = IntPtr.Zero };
            if (args == null || args.Length == 0) return result;

            string first = args[0].Trim();
            string value = null;
            int colon = first.IndexOf(':');
            if (colon >= 0)
            {
                value = first.Substring(colon + 1);
                first = first.Substring(0, colon);
            }
            else if (args.Length > 1)
            {
                value = args[1];
            }

            switch (first.TrimStart('/', '-').ToLowerInvariant())
            {
                case "s": result.Mode = LaunchMode.FullScreen; break;
                case "p":
                case "l": result.Mode = LaunchMode.Preview; break;   // "/l" is an old alias for preview
                case "c": result.Mode = LaunchMode.Configure; break;
                case "w": result.Mode = LaunchMode.Window; break;
                default: result.Mode = LaunchMode.Configure; break;   // "/a" (Win9x password) and unknowns
            }

            if (value != null && long.TryParse(value.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out long h))
                result.Window = new IntPtr(h);
            return result;
        }
    }
}
