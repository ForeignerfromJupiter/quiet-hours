using System;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace QuietHours.Windows
{
    /// The Settings… dialog (/c): the same options as the macOS sheet, minus the style, which is
    /// picked in Windows' own screen saver list.
    sealed class OptionsForm : Form
    {
        const string RuntimeDownload = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";

        readonly StyleInfo style;
        readonly Settings settings;
        readonly ComboBox finish = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList };
        readonly ComboBox hours = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList };
        readonly CheckBox seconds = new CheckBox { Text = "Show seconds", AutoSize = true };
        readonly CheckBox pureBlack = new CheckBox { Text = "Pure black in dark mode (best for OLED screens)", AutoSize = true };

        public OptionsForm(StyleInfo style)
        {
            this.style = style;
            settings = Settings.Load(style);

            Text = "Quiet Hours - " + style.Name;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterParent;
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Font = SystemFonts.MessageBoxFont;
            Padding = new Padding(16);

            finish.Items.AddRange(new object[]
            {
                "Auto (follows Windows app mode)",
                style.DarkFinish + " (dark)",
                style.LightFinish + " (light)",
            });
            finish.SelectedIndex = (int)settings.Finish;

            hours.Items.AddRange(new object[]
            {
                "System (" + (SystemPrefs.Uses24HourClock() ? "24-hour" : "12-hour") + " now)",
                "12-hour",
                "24-hour",
            });
            hours.SelectedIndex = (int)settings.HourCycle;
            FitWidth(finish);
            FitWidth(hours);
            seconds.Checked = settings.ShowSeconds;
            pureBlack.Checked = settings.PureBlack;

            var grid = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Dock = DockStyle.Fill };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            AddRow(grid, "Finish", finish);
            AddRow(grid, "Time", hours);
            AddRow(grid, "", seconds);
            AddRow(grid, "", pureBlack);

            WebViewHost.PrepareLoader();
            if (WebViewHost.RuntimeMissing())
            {
                var link = new LinkLabel
                {
                    Text = "The Microsoft Edge WebView2 Runtime is not installed. Get it from Microsoft",
                    AutoSize = true,
                    MaximumSize = new Size(420, 0),
                    ForeColor = Color.Firebrick,
                };
                link.LinkClicked += (s, e) => Process.Start(new ProcessStartInfo(RuntimeDownload) { UseShellExecute = true });
                grid.Controls.Add(link, 0, grid.RowCount);
                grid.SetColumnSpan(link, 2);
                grid.RowCount++;
            }

            var ok = new Button { Text = "OK", DialogResult = DialogResult.OK, AutoSize = true };
            var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, AutoSize = true };
            var buttons = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 12, 0, 0) };
            buttons.Controls.Add(cancel);
            buttons.Controls.Add(ok);
            grid.Controls.Add(buttons, 0, grid.RowCount);
            grid.SetColumnSpan(buttons, 2);
            grid.RowCount++;

            Controls.Add(grid);
            AcceptButton = ok;
            CancelButton = cancel;
            ok.Click += (s, e) => Save();
        }

        /// Wide enough for the longest item at any DPI (the font is already DPI-scaled).
        void FitWidth(ComboBox box)
        {
            int widest = 0;
            foreach (object item in box.Items)
                widest = Math.Max(widest, TextRenderer.MeasureText(item.ToString(), Font).Width);
            box.Font = Font;
            box.Width = widest + SystemInformation.VerticalScrollBarWidth + 24;
        }

        static void AddRow(TableLayoutPanel grid, string label, Control control)
        {
            int row = grid.RowCount++;
            grid.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 6, 12, 6) }, 0, row);
            control.Margin = new Padding(0, 4, 0, 4);
            grid.Controls.Add(control, 1, row);
        }

        void Save()
        {
            settings.Finish = (Finish)finish.SelectedIndex;
            settings.HourCycle = (HourCycle)hours.SelectedIndex;
            settings.ShowSeconds = seconds.Checked;
            settings.PureBlack = pureBlack.Checked;
            try
            {
                settings.Save(style);
            }
            catch (Exception e)
            {
                Log.Error("Settings.Save", e);
                MessageBox.Show(this, "Could not save settings: " + e.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }
}
