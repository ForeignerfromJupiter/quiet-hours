using System;
using System.Runtime.InteropServices;
using System.Text;

namespace QuietHours.Windows
{
    static class Native
    {
        public const int GWL_STYLE = -16;
        public const int WS_CHILD = 0x40000000;
        public const int WS_POPUP = unchecked((int)0x80000000);
        public const int LOCALE_SSHORTTIME = 0x00000079;

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X, Y; }

        [StructLayout(LayoutKind.Sequential)]
        public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetParent(IntPtr child, IntPtr newParent);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetCursorPos(out POINT point);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetLastInputInfo(ref LASTINPUTINFO info);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
        public static extern int GetWindowLong(IntPtr hWnd, int index);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongW")]
        public static extern int SetWindowLong(IntPtr hWnd, int index, int value);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetLocaleInfoEx(string localeName, int lcType, StringBuilder data, int cchData);

        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        // Windows 10 1607+. Callers catch EntryPointNotFoundException on older systems.
        [DllImport("user32.dll")]
        public static extern IntPtr GetWindowDpiAwarenessContext(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

        /// Make windows created on this thread match `parent`'s DPI awareness, so a child of
        /// another process's dialog (the Settings preview) isn't refused or mis-scaled.
        public static void MatchDpiAwareness(IntPtr parent)
        {
            try
            {
                IntPtr ctx = GetWindowDpiAwarenessContext(parent);
                if (ctx != IntPtr.Zero) SetThreadDpiAwarenessContext(ctx);
            }
            catch (EntryPointNotFoundException)
            {
                // Older than Windows 10 1607: nothing to match.
            }
        }

        /// Any key or mouse button down now, or pressed since the previous call (the low bit).
        /// Keys in `held` (down when the saver settled, e.g. a stuck key) only count once released
        /// and pressed again. Pass `record: true` to refill `held` instead.
        public static bool AnyKeyOrButtonPressed(bool[] held, bool record = false)
        {
            bool any = false;
            for (int vk = 1; vk < 256; vk++)   // no early exit: every call clears every low bit
            {
                short state = GetAsyncKeyState(vk);
                bool down = (state & 0x8000) != 0;
                if (record) { held[vk] = down; continue; }
                if (held[vk])
                {
                    if (!down) held[vk] = false;   // released: from now on it counts
                    continue;
                }
                if ((state & 0x8001) != 0) any = true;
            }
            return any;
        }

        public static uint LastInputTick()
        {
            var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO)) };
            return GetLastInputInfo(ref info) ? info.dwTime : 0;
        }
    }
}
