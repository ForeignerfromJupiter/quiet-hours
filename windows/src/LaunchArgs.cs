using System;
using System.Globalization;

namespace QuietHours.Windows
{
    enum LaunchMode { FullScreen, Preview, Configure, Window }

    /// Screen saver command line. Windows is loose about it: "/s", "/S", "-s", "/p 1234",
    /// "/P:1234", "/p1234", "/c:1234", "/c", or nothing at all (which means configure).
    struct LaunchArgs
    {
        public LaunchMode Mode;
        public IntPtr Window;

        public static LaunchArgs Parse(string[] args)
        {
            var result = new LaunchArgs { Mode = LaunchMode.Configure, Window = IntPtr.Zero };
            if (args == null || args.Length == 0) return result;

            string first = (args[0] ?? "").Trim().TrimStart('/', '-');
            if (first.Length == 0) return result;

            // Letter, then an optional ":1234", "1234" or a separate argument holding the handle.
            char letter = char.ToLowerInvariant(first[0]);
            string value = first.Substring(1).TrimStart(':', '=').Trim();
            if (value.Length == 0 && args.Length > 1) value = args[1];

            switch (letter)
            {
                case 's': result.Mode = LaunchMode.FullScreen; break;
                case 'p':
                case 'l': result.Mode = LaunchMode.Preview; break;   // "/l" is an old alias for preview
                case 'w': result.Mode = LaunchMode.Window; break;
                default: result.Mode = LaunchMode.Configure; break;   // "/c", "/a" (Win9x password), unknowns
            }

            if (value != null && long.TryParse(value.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out long h)
                && h > 0 && (IntPtr.Size == 8 || h <= int.MaxValue))
                result.Window = new IntPtr(h);   // HWNDs fit in 32 bits even in 64-bit processes
            return result;
        }
    }
}
