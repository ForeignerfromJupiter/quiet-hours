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
        public static readonly List<SaverForm> Open = new List<SaverForm>();

        readonly StyleInfo style;
        readonly Settings settings;
        readonly SaverMode mode;
        readonly IntPtr previewParent;
        readonly Rectangle target;
        CoreWebView2Controller controller;
        Timer parentWatch;
        string failure;

        public static List<SaverForm> CreateAll(StyleInfo style, Settings settings, SaverMode mode, IntPtr previewParent)
        {
            var forms = new List<SaverForm>();
            if (mode == SaverMode.FullScreen)
            {
                // Every display shows the clock (Phase 9 on macOS adds a "main display only" option).
                foreach (var screen in Screen.AllScreens)
                    forms.Add(new SaverForm(style, settings, mode, IntPtr.Zero, screen.Bounds));
            }
            else
            {
                forms.Add(new SaverForm(style, settings, mode, previewParent, Rectangle.Empty));
            }
            return forms;
        }

        SaverForm(StyleInfo style, Settings settings, SaverMode mode, IntPtr previewParent, Rectangle target)
        {
            this.style = style;
            this.settings = settings;
            this.mode = mode;
            this.previewParent = previewParent;
            this.target = target;

            Text = "Quiet Hours - " + style.Name;
            BackColor = Color.Black;
            DoubleBuffered = true;
            AutoScaleMode = AutoScaleMode.None;

            switch (mode)
            {
                case SaverMode.FullScreen:
                    FormBorderStyle = FormBorderStyle.None;
                    StartPosition = FormStartPosition.Manual;
                    Bounds = target;
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

        protected override async void OnLoad(EventArgs e)
        {
            base.OnLoad(e);

            if (mode == SaverMode.Preview)
            {
                // Become a child of the Settings dialog's little monitor picture.
                int ws = Native.GetWindowLong(Handle, Native.GWL_STYLE);
                Native.SetWindowLong(Handle, Native.GWL_STYLE, (ws & ~Native.WS_POPUP) | Native.WS_CHILD);
                Native.SetParent(Handle, previewParent);
                Native.GetClientRect(previewParent, out var r);
                Bounds = new Rectangle(0, 0, r.Right - r.Left, r.Bottom - r.Top);
                // The dialog destroys the thumbnail window when it closes or switches saver.
                parentWatch = new Timer { Interval = 500 };
                parentWatch.Tick += (s, a) => { if (!Native.IsWindow(previewParent)) Close(); };
                parentWatch.Start();
            }
            else if (mode == SaverMode.FullScreen)
            {
                Bounds = target;   // again, after any DPI adjustment while the handle was created
            }

            try
            {
                var env = await WebViewHost.Environment();
                if (IsDisposed) return;
                controller = await env.CreateCoreWebView2ControllerAsync(Handle);
                if (IsDisposed) { controller.Close(); return; }

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

                WebViewHost.ServePage(core, env);
                core.WebMessageReceived += OnWebMessage;
                core.NewWindowRequested += (o, a) => a.Handled = true;
                core.Navigate(PageUrl());
                controller.IsVisible = true;
                if (mode == SaverMode.FullScreen) controller.MoveFocus(CoreWebView2MoveFocusReason.Programmatic);
            }
            catch (Exception ex)
            {
                // Usually WebView2RuntimeNotFoundException. Stay black (full screen still exits on input).
                Log.Error("WebView2", ex);
                failure = ex is WebView2RuntimeNotFoundException
                    ? "Quiet Hours needs the Microsoft Edge WebView2 Runtime."
                    : "Quiet Hours could not start: " + ex.Message;
                Invalidate();
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
            if (failure == null || mode == SaverMode.Preview && Width < 200) return;
            TextRenderer.DrawText(e.Graphics, failure, Font, ClientRectangle, Color.FromArgb(140, 140, 140),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            Open.Remove(this);
            parentWatch?.Dispose();
            controller?.Close();
            controller = null;
            base.OnFormClosed(e);
        }

        protected override void OnHandleDestroyed(EventArgs e)
        {
            // In preview the parent dialog may destroy us without a close.
            if (mode == SaverMode.Preview && !IsDisposed && Open.Contains(this))
            {
                Open.Remove(this);
                Application.ExitThread();
            }
            base.OnHandleDestroyed(e);
        }
    }
}
