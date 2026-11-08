using System;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Windows.Forms;

namespace QuietHours.Windows
{
    /// Entry point. Windows runs a screen saver as:
    ///   /s            full screen on every display (also the default for a double-click)
    ///   /p <hwnd>     live thumbnail inside the Screen Saver Settings dialog
    ///   /c[:<hwnd>]   Settings… button (no arguments at all means the same)
    /// plus /w for development: a normal 1280×800 window.
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            // Must run before any method that touches a WebView2 type is JIT-compiled.
            EmbeddedAssemblies.Install();
            return Run(args);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        static int Run(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.ThreadException += (s, e) => Log.Error("UI thread", e.Exception);
            AppDomain.CurrentDomain.UnhandledException += (s, e) => Log.Error("Unhandled", e.ExceptionObject as Exception);

            var launch = LaunchArgs.Parse(args);
            var style = StyleInfo.Current;
            Log.Info($"{style.Name}: {launch.Mode} {launch.Window}");

            switch (launch.Mode)
            {
                case LaunchMode.Configure:
                    using (var dialog = new OptionsForm(style))
                    {
                        if (launch.Window != IntPtr.Zero) dialog.ShowDialog(new OwnerWindow(launch.Window));
                        else dialog.ShowDialog();
                    }
                    return 0;

                case LaunchMode.Preview:
                    if (launch.Window == IntPtr.Zero || !Native.IsWindow(launch.Window)) return 1;
                    return RunSaver(style, SaverMode.Preview, launch.Window);

                case LaunchMode.Window:
                    return RunSaver(style, SaverMode.Window, IntPtr.Zero);

                default:
                    // Windows can start /s again while a saver is already up; keep exactly one.
                    using (var mutex = new Mutex(true, @"Local\QuietHours.Screensaver", out bool first))
                    {
                        if (!first) return 0;
                        return RunSaver(style, SaverMode.FullScreen, IntPtr.Zero);
                    }
            }
        }

        static int RunSaver(StyleInfo style, SaverMode mode, IntPtr previewParent)
        {
            WebViewHost.PrepareLoader();
            var settings = Settings.Load(style);
            var context = new ApplicationContext();
            var forms = SaverForm.CreateAll(style, settings, mode, previewParent);
            int open = forms.Count;
            foreach (var f in forms)
            {
                f.FormClosed += (s, e) => { if (--open == 0) context.ExitThread(); };
                f.Show();
            }

            InputWatcher watcher = null;
            if (mode == SaverMode.FullScreen)
            {
                Cursor.Hide();
                watcher = new InputWatcher(Exit);
            }
            SystemWatcher.Start(forms);

            Application.Run(context);

            watcher?.Dispose();
            SystemWatcher.Stop();
            return 0;
        }

        /// Close every window: the saver ends as one, on all displays.
        public static void Exit()
        {
            foreach (var f in SaverForm.Open.ToArray()) f.Close();
        }
    }

    sealed class OwnerWindow : IWin32Window
    {
        public OwnerWindow(IntPtr handle) { Handle = handle; }
        public IntPtr Handle { get; }
    }
}
