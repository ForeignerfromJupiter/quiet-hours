using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;

namespace QuietHours.Windows
{
    enum SaverMode { FullScreen, Preview, Window }

    /// One window showing the style: a borderless top-most window per display (/s), a child of
    /// the Settings dialog's thumbnail (/p), or a normal window (/w). Each hosts a WebView2
    /// running windows/web/index.html.
    sealed class SaverForm : Form
    {
        /// Every saver window still open. The process ends when this empties.
        public static readonly List<SaverForm> Open = new List<SaverForm>();

        readonly StyleInfo style;
        readonly Settings settings;
        readonly SaverMode mode;
        readonly IntPtr previewParent;
        Rectangle target;
        CoreWebView2Controller controller;
        Timer parentWatch;
        string failure;

        /// The display this window covers (full screen only).
        public string DeviceName { get; }

        public static SaverForm ForScreen(StyleInfo style, Settings settings, Screen screen) =>
            new SaverForm(style, settings, SaverMode.FullScreen, IntPtr.Zero, screen.Bounds, screen.DeviceName);

        public static SaverForm Single(StyleInfo style, Settings settings, SaverMode mode, IntPtr previewParent) =>
            new SaverForm(style, settings, mode, previewParent, Rectangle.Empty, null);

        SaverForm(StyleInfo style, Settings settings, SaverMode mode, IntPtr previewParent, Rectangle target, string deviceName)
        {
            this.style = style;
            this.settings = settings;
            this.mode = mode;
            this.previewParent = previewParent;
            this.target = target;
            DeviceName = deviceName;

            Text = "Quiet Hours - " + style.Name;
            BackColor = Color.Black;
            ForeColor = Color.FromArgb(150, 150, 150);
            DoubleBuffered = true;
            AutoScaleMode = AutoScaleMode.None;

            switch (mode)
            {
                case SaverMode.FullScreen:
                    FormBorderStyle = FormBorderStyle.None;
                    StartPosition = FormStartPosition.Manual;
                    Bounds = target;   // physical pixels: the process is per-monitor DPI aware (app.manifest)
                    TopMost = true;
                    ShowInTaskbar = false;
                    KeyPreview = true;
                    break;
                case SaverMode.Preview:
                    FormBorderStyle = FormBorderStyle.None;
                    StartPosition = FormStartPosition.Manual;
                    ShowInTaskbar = false;
                    break;
                case SaverMode.Window:
                    StartPosition = FormStartPosition.CenterScreen;
                    ClientSize = new Size(1280, 800);
                    KeyPreview = true;
                    break;
            }
            Open.Add(this);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            if (mode != SaverMode.Preview) return;

            // Become a child of the Settings dialog's little monitor picture before ever being shown.
            int ws = Native.GetWindowLong(Handle, Native.GWL_STYLE);
            Native.SetWindowLong(Handle, Native.GWL_STYLE, (ws & ~Native.WS_POPUP) | Native.WS_CHILD);
            Native.SetParent(Handle, previewParent);
            FitPreviewParent();

            // The dialog destroys the thumbnail (and so this window) when it closes or switches
            // saver; this timer is the backstop, and follows the thumbnail if it resizes.
            parentWatch = new Timer { Interval = 250 };
            parentWatch.Tick += (s, a) =>
            {
                if (!Native.IsWindow(previewParent)) Close();
                else FitPreviewParent();
            };
            parentWatch.Start();
        }

        void FitPreviewParent()
        {
            if (!Native.GetClientRect(previewParent, out var r)) return;
            var want = new Rectangle(0, 0, Math.Max(1, r.Right - r.Left), Math.Max(1, r.Bottom - r.Top));
            if (Bounds != want) Bounds = want;
        }

        /// The display changed resolution or moved.
        public void Retarget(Rectangle bounds)
        {
            target = bounds;
            if (Bounds != bounds) Bounds = bounds;
        }

        protected override async void OnLoad(EventArgs e)
        {
            base.OnLoad(e);
            if (mode == SaverMode.FullScreen) Bounds = target;   // again, in case the handle's creation adjusted it

            try
            {
                var env = await WebViewHost.Environment();
                if (IsDisposed) return;
                var created = await env.CreateCoreWebView2ControllerAsync(Handle);
                if (IsDisposed) { created.Close(); return; }
                controller = created;

                controller.DefaultBackgroundColor = Color.Black;
                controller.Bounds = ClientRectangle;
                var core = controller.CoreWebView2;
                var s = core.Settings;
                s.AreDevToolsEnabled = mode == SaverMode.Window;
                s.AreDefaultContextMenusEnabled = false;
                s.AreDefaultScriptDialogsEnabled = false;
                s.AreBrowserAcceleratorKeysEnabled = false;
                s.IsStatusBarEnabled = false;
                s.IsZoomControlEnabled = false;
                s.IsPinchZoomEnabled = false;
                s.IsSwipeNavigationEnabled = false;
                s.IsBuiltInErrorPageEnabled = false;
                s.IsGeneralAutofillEnabled = false;
                s.IsPasswordAutosaveEnabled = false;
                // No SmartScreen URL lookups: the page is local and the saver never contacts anyone.
                s.IsReputationCheckingRequired = false;

                WebViewHost.ServePage(core, env);
                core.WebMessageReceived += OnWebMessage;
                core.NewWindowRequested += (o, a) => a.Handled = true;
                core.ProcessFailed += OnProcessFailed;
                core.Navigate(PageUrl());
                controller.IsVisible = true;
                if (mode == SaverMode.FullScreen && ContainsFocus) controller.MoveFocus(CoreWebView2MoveFocusReason.Programmatic);
            }
            catch (Exception ex)
            {
                // Typically WebView2RuntimeNotFoundException. Stay black with a short note; full
                // screen still exits on input through InputWatcher.
                Log.Error("WebView2", ex);
                failure = ex is WebView2RuntimeNotFoundException
                    ? (mode == SaverMode.Preview
                        ? "Needs WebView2"
                        : "Quiet Hours needs the Microsoft Edge WebView2 Runtime.\nInstall it from Microsoft (the screen saver's Settings… button has a link), then try again.")
                    : (mode == SaverMode.Preview ? "Could not start" : "Quiet Hours could not start.\nDetails: " + Log.FilePath);
                Invalidate();
            }
        }

        void OnProcessFailed(object sender, CoreWebView2ProcessFailedEventArgs e)
        {
            // A crashed renderer leaves a frozen frame; reload once it's gone.
            Log.Info("WebView2 process failed: " + e.ProcessFailedKind);
            if (e.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessExited
                || e.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessUnresponsive)
            {
                try { controller?.CoreWebView2?.Reload(); }
                catch (Exception ex) { Log.Error("Reload", ex); }
            }
        }

        string PageUrl()
        {
            string Flag(bool b) => b ? "1" : "0";
            var q = new List<string>
            {
                "style=" + style.Id,
                "finish=" + settings.Finish.ToString().ToLowerInvariant(),
                "dark=" + Flag(SystemPrefs.IsDarkMode()),
                "h24=" + Flag(settings.Uses24Hour()),
                "secs=" + Flag(settings.ShowSeconds),
                "pure=" + Flag(settings.PureBlack),
                "mode=" + (mode == SaverMode.FullScreen ? "s" : mode == SaverMode.Preview ? "p" : "w"),
            };
            return WebViewHost.Origin + "index.html?" + string.Join("&", q);
        }

        /// Windows theme or time format changed: tell the page (it remounts on a finish change).
        public void PushSystemPrefs()
        {
            if (controller?.CoreWebView2 == null) return;
            string json = string.Format(CultureInfo.InvariantCulture, "{{\"dark\":{0},\"h24\":{1}}}",
                SystemPrefs.IsDarkMode() ? "true" : "false",
                settings.Uses24Hour() ? "true" : "false");
            try { controller.CoreWebView2.PostWebMessageAsJson(json); }
            catch (Exception e) { Log.Error("PostWebMessage", e); }
        }

        void OnWebMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            string msg;
            try { msg = e.TryGetWebMessageAsString(); }
            catch (ArgumentException) { return; }
            if (msg == "exit" && mode == SaverMode.FullScreen) Program.Exit();
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (controller != null) controller.Bounds = ClientRectangle;
            if (failure != null) Invalidate();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (mode == SaverMode.FullScreen) Program.Exit();
            else if (mode == SaverMode.Window && e.KeyCode == Keys.Escape) Close();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (mode == SaverMode.FullScreen) Program.Exit();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (failure == null) return;
            using (var font = new Font(FontFamily.GenericSansSerif, mode == SaverMode.Preview ? 7f : 14f))
                TextRenderer.DrawText(e.Graphics, failure, font, ClientRectangle, ForeColor,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            Open.Remove(this);
            Release();
            base.OnFormClosed(e);
        }

        protected override void OnHandleDestroyed(EventArgs e)
        {
            // In preview the Settings dialog destroys us (as its child) without a close message.
            if (Open.Remove(this))
            {
                Release();
                if (Open.Count == 0) Application.ExitThread();
            }
            base.OnHandleDestroyed(e);
        }

        void Release()
        {
            parentWatch?.Dispose();
            parentWatch = null;
            try { controller?.Close(); }
            catch (Exception ex) { Log.Error("Controller.Close", ex); }
            controller = null;
        }
    }
}
