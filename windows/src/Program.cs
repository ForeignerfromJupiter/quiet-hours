using System;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Windows.Forms;

namespace QuietHours.Windows
{
    /// Entry point. Windows runs a screen saver as:
    ///   /s            full screen on every display (also what a double-click or "Test" does)
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
            try
            {
                return Run(args);
            }
            catch (Exception e)
            {
                // Last resort: never leave a frozen black screen or a silent crash.
                Log.Error("Fatal", e);
                if (args.Length == 0 || LaunchArgs.Parse(args).Mode == LaunchMode.Configure)
                    MessageBox.Show("Quiet Hours could not start:\n\n" + e.Message + "\n\nDetails are in " + Log.FilePath,
                        "Quiet Hours", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        static int Run(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += (s, e) => Log.Error("UI thread", e.Exception);
            AppDomain.CurrentDomain.UnhandledException += (s, e) => Log.Error("Unhandled", e.ExceptionObject as Exception);

            var launch = LaunchArgs.Parse(args);
            var style = StyleInfo.Current;
            Log.Info($"{style.Name} {typeof(Program).Assembly.GetName().Version}: {launch.Mode} {launch.Window} ({string.Join(" ", args)})");

            switch (launch.Mode)
            {
                case LaunchMode.Configure:
                    // "/c" with no handle: Windows expects the dialog to be owned by the foreground window.
                    IntPtr owner = launch.Window != IntPtr.Zero ? launch.Window : Native.GetForegroundWindow();
                    using (var dialog = new OptionsForm(style))
                    {
                        if (owner != IntPtr.Zero && Native.IsWindow(owner)) dialog.ShowDialog(new OwnerWindow(owner));
                        else dialog.ShowDialog();
                    }
                    return 0;

                case LaunchMode.Preview:
                    if (launch.Window == IntPtr.Zero || !Native.IsWindow(launch.Window)) return 1;
                    Native.MatchDpiAwareness(launch.Window);
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

        static ApplicationContext context;
        static StyleInfo runningStyle;
        static Settings runningSettings;

        static int RunSaver(StyleInfo style, SaverMode mode, IntPtr previewParent)
        {
            WebViewHost.PrepareLoader();
            runningStyle = style;
            runningSettings = Settings.Load(style);
            context = new ApplicationContext();

            if (mode == SaverMode.FullScreen)
            {
                foreach (var screen in Screen.AllScreens) Show(SaverForm.ForScreen(style, runningSettings, screen));
                // Keyboard focus on the primary display's window (the page also listens for keys).
                SaverForm.Open.FirstOrDefault(f => f.DeviceName == Screen.PrimaryScreen.DeviceName)?.Activate();
            }
            else
            {
                Show(SaverForm.Single(style, runningSettings, mode, previewParent));
            }

            InputWatcher watcher = null;
            if (mode == SaverMode.FullScreen)
            {
                Cursor.Hide();
                watcher = new InputWatcher(Exit);
                DisplayWatcher.Start(Reconcile);
            }
            SystemWatcher.Start();

            Application.Run(context);

            watcher?.Dispose();
            DisplayWatcher.Stop();
            SystemWatcher.Stop();
            return 0;
        }

        static void Show(SaverForm form)
        {
            // The saver ends when its last window closes (or the preview's parent goes away).
            form.FormClosed += (s, e) => { if (SaverForm.Open.Count == 0) context.ExitThread(); };
            form.Show();
        }

        /// Displays came or went (a monitor slept, a laptop docked, a resolution changed): one
        /// window per display, each covering it exactly. New windows are added before stale
        /// ones close, so the saver never ends by accident.
        static void Reconcile()
        {
            var screens = Screen.AllScreens;
            foreach (var screen in screens)
            {
                var form = SaverForm.Open.FirstOrDefault(f => f.DeviceName == screen.DeviceName);
                if (form != null) form.Retarget(screen.Bounds);
                else Show(SaverForm.ForScreen(runningStyle, runningSettings, screen));
            }
            foreach (var form in SaverForm.Open.ToArray())
                if (!screens.Any(s => s.DeviceName == form.DeviceName)) form.Close();
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
