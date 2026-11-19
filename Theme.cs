using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace DriverLoom.UI
{
    public static class Palette
    {
        public static bool Dark = true;
        public static string Preference = "Dark";
        public static Color Background, Surface, Input, Border, Text, Muted, Accent, AccentSurface, Selected, Positive, Primary, OnPrimary;
        public static void Select(string preference)
        {
            Preference = preference;
            Dark = preference != "Light";
            if (preference == "System")
            {
                try { using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                    { Dark = key == null || Convert.ToInt32(key.GetValue("AppsUseLightTheme", 0)) == 0; } }
                catch { Dark = true; }
            }
            Background = ColorTranslator.FromHtml(Dark ? "#111315" : "#F4F5F7");
            Surface = ColorTranslator.FromHtml(Dark ? "#171A1E" : "#FFFFFF");
            Input = ColorTranslator.FromHtml(Dark ? "#0D0F11" : "#F8F9FB");
            Border = ColorTranslator.FromHtml(Dark ? "#30353C" : "#D8DDE4");
            Text = ColorTranslator.FromHtml(Dark ? "#F2F3F5" : "#18202B");
            Muted = ColorTranslator.FromHtml(Dark ? "#9DA5AF" : "#586574");
            Accent = ColorTranslator.FromHtml(Dark ? "#83B3FF" : "#205DC2");
            AccentSurface = ColorTranslator.FromHtml(Dark ? "#192A43" : "#E8F0FF");
            Selected = ColorTranslator.FromHtml(Dark ? "#202B3B" : "#EAF1FC");
            Positive = ColorTranslator.FromHtml(Dark ? "#8CCAA8" : "#216A45");
            Primary = ColorTranslator.FromHtml(Dark ? "#F6F7F9" : "#18202B");
            OnPrimary = ColorTranslator.FromHtml(Dark ? "#101216" : "#FFFFFF");
        }
    }

    public class ActionButton : Button
    {
        public bool Primary { get; set; }
        protected override void OnPaint(PaintEventArgs e)
        {
            if (Enabled) { base.OnPaint(e); return; }
            e.Graphics.Clear(Palette.Background);
            using (Pen pen = new Pen(Palette.Border)) e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
            TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, Palette.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        }
    }

    public class MainWindow : Form
    {
        public MainWindow() { FormBorderStyle = FormBorderStyle.None; DoubleBuffered = true; Padding = new Padding(1); }
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); MaximizedBounds = Screen.FromHandle(Handle).WorkingArea; }
        protected override void OnPaint(PaintEventArgs e) { base.OnPaint(e); using (Pen pen = new Pen(Palette.Border)) e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1); }
        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg == 0x84 && WindowState == FormWindowState.Normal)
            {
                Point p = PointToClient(new Point((short)((long)m.LParam & 65535), (short)(((long)m.LParam >> 16) & 65535)));
                int edge = 7; bool left = p.X < edge, right = p.X >= Width - edge, top = p.Y < edge, bottom = p.Y >= Height - edge;
                if (left || right || top || bottom) m.Result = new IntPtr(top ? (left ? 13 : right ? 14 : 12) : bottom ? (left ? 16 : right ? 17 : 15) : left ? 10 : 11);
            }
        }
    }
    public class TitleBar : Panel
    {
        public Image Artwork { get; set; }
        [DllImport("user32.dll")] static extern bool ReleaseCapture();
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
        public TitleBar() { DoubleBuffered = true; Height = 56; AccessibleName = "DriverLoom title bar"; }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(Color.FromArgb(13, 15, 20));
            if (Artwork != null)
            {
                // Display the supplied wordmark directly from the unmodified brand sheet.
                e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                e.Graphics.DrawImage(Artwork, new Rectangle(20, 13, 208, 29), new Rectangle(204, 196, 1348, 196), GraphicsUnit.Pixel);
            }
            using (Pen pen = new Pen(Palette.Border)) { e.Graphics.DrawLine(pen, 246, 0, 246, Height); e.Graphics.DrawLine(pen, 0, Height - 1, Width, Height - 1); }
            using (Font font = new Font("Consolas", 9, FontStyle.Bold)) TextRenderer.DrawText(e.Graphics, "HARDWARE UPDATES", font, new Point(266, 21), Color.FromArgb(157, 165, 175), TextFormatFlags.NoPrefix);
        }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); if (e.Button == MouseButtons.Left) { ReleaseCapture(); SendMessage(FindForm().Handle, 0xA1, new IntPtr(2), IntPtr.Zero); } }
        protected override void OnMouseDoubleClick(MouseEventArgs e) { base.OnMouseDoubleClick(e); Form f = FindForm(); f.WindowState = f.WindowState == FormWindowState.Maximized ? FormWindowState.Normal : FormWindowState.Maximized; }
    }
    public class IconButton : Button
    {
        public string Glyph { get; set; }
        public bool Chrome { get; set; }
        bool hover;
        public IconButton() { FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0; Cursor = Cursors.Hand; TabStop = true; }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Color bg = Chrome ? Color.FromArgb(13, 15, 20) : Palette.Background;
            if (hover) bg = Glyph == "Close" ? Color.FromArgb(180, 38, 51) : Chrome ? Color.FromArgb(40, 45, 54) : Palette.Selected;
            e.Graphics.Clear(bg); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Color color = !Enabled ? Palette.Muted : Chrome ? Color.FromArgb(225, 229, 236) : Palette.Muted;
            float x = Width / 2f, y = Height / 2f;
            using (Pen pen = new Pen(color, 1.4f))
            {
                if (Glyph == "Close") { e.Graphics.DrawLine(pen, x - 4, y - 4, x + 4, y + 4); e.Graphics.DrawLine(pen, x + 4, y - 4, x - 4, y + 4); }
                else if (Glyph == "Minimize") e.Graphics.DrawLine(pen, x - 5, y, x + 5, y);
                else if (Glyph == "Maximize") e.Graphics.DrawRectangle(pen, x - 4, y - 4, 8, 8);
                else if (Glyph == "Settings")
                {
                    PointF[] points = new PointF[32];
                    for (int i = 0; i < points.Length; i++) { double angle = i * Math.PI / 16; float radius = (i % 4 == 1 || i % 4 == 2) ? 8.3f : 6.5f; points[i] = new PointF(x + radius * (float)Math.Cos(angle), y + radius * (float)Math.Sin(angle)); }
                    e.Graphics.DrawPolygon(pen, points); e.Graphics.DrawEllipse(pen, x - 2.5f, y - 2.5f, 5, 5);
                }
                else if (Glyph == "Refresh") { e.Graphics.DrawArc(pen, x - 7, y - 7, 14, 14, -80, 290); e.Graphics.DrawLines(pen, new PointF[] { new PointF(x - 1, y - 11), new PointF(x + 1, y - 6), new PointF(x - 4, y - 5) }); }
                else if (Image != null) e.Graphics.DrawImage(Image, x - 9, y - 9, 18, 18);
                if (Focused) { pen.Color = Palette.Accent; e.Graphics.DrawLine(pen, x - 5, Height - 4, x + 5, Height - 4); }
            }
        }
    }

    public static class Theme
    {
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr handle, int attribute, ref int value, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr handle, string app, string id);
        static void PaintChoice(object sender, DrawItemEventArgs e)
        {
            ComboBox combo = (ComboBox)sender;
            Color background = (e.State & DrawItemState.Selected) != 0 ? Palette.Selected : Palette.Input;
            using (SolidBrush brush = new SolidBrush(background)) e.Graphics.FillRectangle(brush, e.Bounds);
            string text = e.Index >= 0 ? Convert.ToString(combo.Items[e.Index]) : combo.Text;
            TextRenderer.DrawText(e.Graphics, text, combo.Font, e.Bounds, Palette.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            e.DrawFocusRectangle();
        }
        public static void Apply(Control control)
        {
            control.BackColor = Palette.Background;
            control.ForeColor = Palette.Text;
            Form form = control as Form;
            if (form != null) { try { int dark = Palette.Dark ? 1 : 0; DwmSetWindowAttribute(form.Handle, 20, ref dark, 4); } catch { } }
            if (control is Panel || control is TableLayoutPanel || control is FlowLayoutPanel)
                control.BackColor = (string.Equals(control.Tag as string, "Card")) ? Palette.Surface : Palette.Background;
            Label label = control as Label;
            if (label != null) { label.BackColor = Color.Transparent; label.UseMnemonic = false; if ((label.Tag as string) == "Muted") label.ForeColor = Palette.Muted; if ((label.Tag as string) == "Accent") label.ForeColor = Palette.Accent; }
            Button button = control as Button;
            if (button != null)
            {
                ActionButton action = button as ActionButton;
                bool primary = action != null && action.Primary;
                button.UseVisualStyleBackColor = false;
                button.FlatStyle = FlatStyle.Flat; button.UseMnemonic = false;
                button.FlatAppearance.BorderSize = 1; button.FlatAppearance.BorderColor = Palette.Border;
                button.BackColor = primary ? Palette.Primary : Palette.Background;
                button.ForeColor = primary ? Palette.OnPrimary : Palette.Text;
                button.FlatAppearance.MouseOverBackColor = primary ? (Palette.Dark ? Color.White : Color.FromArgb(44, 56, 73)) : Palette.Selected;
                button.FlatAppearance.MouseDownBackColor = primary ? (Palette.Dark ? Color.FromArgb(210, 220, 234) : Color.Black) : Palette.AccentSurface;
                button.Cursor = Cursors.Hand;
            }
            CheckBox checkBox = control as CheckBox;
            if (checkBox != null) checkBox.BackColor = Color.Transparent;
            RadioButton radio = control as RadioButton;
            if (radio != null)
            {
                radio.FlatStyle = FlatStyle.Flat; radio.UseMnemonic = false;
                radio.FlatAppearance.BorderColor = Palette.Border;
                radio.BackColor = radio.Checked ? Palette.Primary : Palette.Background;
                radio.ForeColor = radio.Checked ? Palette.OnPrimary : Palette.Muted;
                radio.FlatAppearance.CheckedBackColor = Palette.Primary;
                radio.FlatAppearance.MouseOverBackColor = radio.Checked ? Palette.Primary : Palette.Selected;
            }
            TextBox box = control as TextBox;
            if (box != null) { box.BackColor = Palette.Input; box.ForeColor = Palette.Text; box.BorderStyle = BorderStyle.FixedSingle; }
            ComboBox combo = control as ComboBox;
            if (combo != null) { combo.BackColor = Palette.Input; combo.ForeColor = Palette.Text; combo.FlatStyle = FlatStyle.Flat; combo.DrawMode = DrawMode.OwnerDrawFixed; combo.ItemHeight = combo.Font.Height + 8; combo.DrawItem -= PaintChoice; combo.DrawItem += PaintChoice; }
            ScrollableControl scrolling = control as ScrollableControl;
            if (scrolling != null && scrolling.AutoScroll) { try { SetWindowTheme(scrolling.Handle, Palette.Dark ? "DarkMode_Explorer" : "Explorer", null); } catch { } }
            DataGridView grid = control as DataGridView;
            if (grid != null)
            {
                try { SetWindowTheme(grid.Handle, Palette.Dark ? "DarkMode_Explorer" : "Explorer", null); } catch { }
                grid.EnableHeadersVisualStyles = false; grid.BorderStyle = BorderStyle.None;
                grid.BackgroundColor = Palette.Background; grid.GridColor = Palette.Border;
                grid.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
                grid.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.Single;
                grid.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.DisableResizing;
                grid.ColumnHeadersHeight = 42;
                grid.ColumnHeadersDefaultCellStyle.BackColor = Palette.Background;
                grid.ColumnHeadersDefaultCellStyle.ForeColor = Palette.Muted;
                grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = Palette.Background;
                grid.ColumnHeadersDefaultCellStyle.SelectionForeColor = Palette.Muted;
                grid.ColumnHeadersDefaultCellStyle.Font = new Font("Consolas", 9, FontStyle.Bold);
                grid.ColumnHeadersDefaultCellStyle.Padding = new Padding(14, 0, 8, 0);
                grid.DefaultCellStyle.BackColor = Palette.Background; grid.DefaultCellStyle.ForeColor = Palette.Text;
                grid.DefaultCellStyle.SelectionBackColor = Palette.Selected; grid.DefaultCellStyle.SelectionForeColor = Palette.Text;
                grid.DefaultCellStyle.Padding = new Padding(14, 8, 8, 8);
                grid.AlternatingRowsDefaultCellStyle.BackColor = Palette.Background;
                foreach (DataGridViewRow row in grid.Rows) row.DefaultCellStyle.BackColor = Color.Empty;
            }
            ToolStrip strip = control as ToolStrip;
            if (strip != null) { strip.Renderer = new MenuRenderer(); strip.BackColor = Palette.Surface; strip.ForeColor = Palette.Text; }
            foreach (Control child in control.Controls) Apply(child);
            control.Invalidate(true);
        }
    }

    public class MenuRenderer : ToolStripProfessionalRenderer
    {
        public MenuRenderer() : base(new MenuColors()) { }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) { e.TextColor = e.Item.Enabled ? Palette.Text : Palette.Muted; base.OnRenderItemText(e); }
    }
    class MenuColors : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return Palette.Surface; } }
        public override Color ImageMarginGradientBegin { get { return Palette.Surface; } }
        public override Color ImageMarginGradientMiddle { get { return Palette.Surface; } }
        public override Color ImageMarginGradientEnd { get { return Palette.Surface; } }
        public override Color MenuItemSelected { get { return Palette.Selected; } }
        public override Color MenuItemBorder { get { return Palette.Border; } }
        public override Color MenuBorder { get { return Palette.Border; } }
    }

    public class DeviceGrid : DataGridView
    {
        public bool Decorated { get; set; }
        public DeviceGrid() { DoubleBuffered = true; }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (Decorated && Rows.Count == 0)
            {
                Rectangle text = new Rectangle(24, ColumnHeadersHeight + 60, Math.Max(1, Width - 48), 60);
                using (Font font = new Font("Segoe UI", 11)) TextRenderer.DrawText(e.Graphics, "Your hardware results will appear here.\r\nUse the refresh arrow to check for updates.", font, text, Palette.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            }
        }
        protected override void OnCellPainting(DataGridViewCellPaintingEventArgs e)
        {
            if (!Decorated || e.RowIndex < 0 || e.ColumnIndex < 0) { base.OnCellPainting(e); return; }
            string column = Columns[e.ColumnIndex].Name;
            if (column != "Device" && column != "Status" && column != "Source") { base.OnCellPainting(e); return; }
            e.PaintBackground(e.ClipBounds, true);
            Rectangle bounds = e.CellBounds;
            string value = Convert.ToString(e.FormattedValue);
            Graphics g = e.Graphics;
            if (column == "Device")
            {
                Rectangle icon = new Rectangle(bounds.X + 16, bounds.Y + (bounds.Height - 32) / 2, 32, 32);
                DrawDevice(g, icon, Convert.ToString(Rows[e.RowIndex].Cells[e.ColumnIndex].Tag) + " " + value);
                Rectangle title = new Rectangle(bounds.X + 62, bounds.Y + 12, Math.Max(1, bounds.Width - 76), 25);
                using (Font font = new Font("Segoe UI", 10, FontStyle.Bold)) TextRenderer.DrawText(g, value, font, title, Palette.Text, TextFormatFlags.EndEllipsis | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                Rectangle meta = new Rectangle(title.X, bounds.Y + 38, title.Width, 21);
                using (Font font = new Font("Segoe UI", 9)) TextRenderer.DrawText(g, Convert.ToString(Rows[e.RowIndex].Cells[e.ColumnIndex].Tag), font, meta, Palette.Muted, TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }
            else if (column == "Status")
            {
                bool update = value == "UPDATE AVAILABLE" || value == "READY TO INSTALL";
                Color color = update ? Palette.Accent : value == "UP TO DATE" ? Palette.Positive : Palette.Muted;
                using (Font font = new Font("Consolas", 8.5f, FontStyle.Bold))
                {
                    Size size = TextRenderer.MeasureText(value, font);
                    Rectangle pill = new Rectangle(bounds.X + 14, bounds.Y + (bounds.Height - 24) / 2, Math.Min(size.Width + 10, bounds.Width - 24), 24);
                    using (SolidBrush brush = new SolidBrush(update ? Palette.AccentSurface : Palette.Surface)) g.FillRectangle(brush, pill);
                    using (Pen pen = new Pen(update ? Palette.AccentSurface : Palette.Border)) g.DrawRectangle(pen, pill);
                    TextRenderer.DrawText(g, value, font, pill, color, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
                }
            }
            else
            {
                bool active = Convert.ToString(Rows[e.RowIndex].Cells["Status"].Value) == "UPDATE AVAILABLE";
                bool link = Convert.ToString(Rows[e.RowIndex].Cells[e.ColumnIndex].Tag) == "Link";
                Rectangle button = new Rectangle(bounds.X + 10, bounds.Y + (bounds.Height - 32) / 2, Math.Max(1, bounds.Width - 24), 32);
                using (SolidBrush brush = new SolidBrush(active ? Palette.Primary : Palette.Background)) g.FillRectangle(brush, button);
                using (Pen pen = new Pen(Palette.Border)) g.DrawRectangle(pen, button);
                using (Font font = new Font("Consolas", 8.5f, FontStyle.Bold)) TextRenderer.DrawText(g, value.ToUpperInvariant(), font, button, active ? Palette.OnPrimary : link ? Palette.Text : Palette.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            }
            using (Pen line = new Pen(Palette.Border)) g.DrawLine(line, bounds.Left, bounds.Bottom - 1, bounds.Right, bounds.Bottom - 1);
            if ((e.State & DataGridViewElementStates.Selected) != 0 && column == "Device")
                using (SolidBrush brush = new SolidBrush(Palette.Accent)) g.FillRectangle(brush, bounds.Left, bounds.Top, 2, bounds.Height - 1);
            e.Handled = true;
        }
        static void DrawDevice(Graphics g, Rectangle r, string kind)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen pen = new Pen(Palette.Muted, 1.5f))
            {
                if (kind.IndexOf("Storage", StringComparison.OrdinalIgnoreCase) >= 0)
                { g.DrawRectangle(pen, r.X + 5, r.Y + 5, 22, 23); g.DrawLine(pen, r.X + 9, r.Y + 22, r.X + 23, r.Y + 22); g.DrawEllipse(pen, r.X + 21, r.Y + 10, 2, 2); }
                else if (kind.IndexOf("Audio", StringComparison.OrdinalIgnoreCase) >= 0)
                { g.DrawLines(pen, new Point[] { new Point(r.X+5,r.Y+13),new Point(r.X+11,r.Y+13),new Point(r.X+17,r.Y+7),new Point(r.X+17,r.Y+25),new Point(r.X+11,r.Y+19),new Point(r.X+5,r.Y+19),new Point(r.X+5,r.Y+13) }); g.DrawArc(pen,r.X+17,r.Y+9,10,14,-65,130); }
                else if (kind.IndexOf("Wi-Fi", StringComparison.OrdinalIgnoreCase) >= 0 || kind.IndexOf("Wireless", StringComparison.OrdinalIgnoreCase) >= 0)
                { g.DrawArc(pen, r.X + 3, r.Y + 6, 26, 23, 214, 112); g.DrawArc(pen, r.X + 9, r.Y + 12, 14, 13, 214, 112); g.DrawEllipse(pen, r.X + 15, r.Y + 23, 2, 2); }
                else if (kind.IndexOf("Network", StringComparison.OrdinalIgnoreCase) >= 0)
                { g.DrawRectangle(pen,r.X+5,r.Y+8,22,16);g.DrawLine(pen,r.X+10,r.Y+8,r.X+10,r.Y+14);g.DrawLine(pen,r.X+16,r.Y+8,r.X+16,r.Y+14);g.DrawLine(pen,r.X+22,r.Y+8,r.X+22,r.Y+14);g.DrawLine(pen,r.X+12,r.Y+24,r.X+12,r.Y+28);g.DrawLine(pen,r.X+20,r.Y+24,r.X+20,r.Y+28); }
                else if (kind.IndexOf("GPU", StringComparison.OrdinalIgnoreCase) >= 0)
                { g.DrawRectangle(pen,r.X+3,r.Y+6,26,18);g.DrawLine(pen,r.X+16,r.Y+24,r.X+16,r.Y+29);g.DrawLine(pen,r.X+10,r.Y+29,r.X+22,r.Y+29); }
                else { g.DrawRectangle(pen, r.X + 7, r.Y + 7, 18, 18); for (int i = 11; i <= 23; i += 6) { g.DrawLine(pen, r.X + 3, r.Y + i, r.X + 7, r.Y + i); g.DrawLine(pen, r.X + 25, r.Y + i, r.X + 29, r.Y + i); g.DrawLine(pen, r.X + i, r.Y + 3, r.X + i, r.Y + 7); g.DrawLine(pen, r.X + i, r.Y + 25, r.X + i, r.Y + 29); } }
            }
            g.SmoothingMode = SmoothingMode.Default;
        }
    }
}
