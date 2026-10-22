using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows;
using WinForms = System.Windows.Forms;

namespace WattLite;

// Win11 任务栏由 XAML 合成层渲染，SetParent 进 Shell_TrayWnd 会被盖住
// （TrafficMonitor 同样问题，V1.5+ 改用悬浮窗方案）：
// 用置顶无边框小窗悬浮在任务栏托盘区左侧，常驻绘制功率文本
public sealed class TaskbarBadge : IDisposable
{
    public Action? TogglePanel;
    public Action? OpenSettings;

    private readonly BadgeForm _form;
    private readonly WinForms.Timer _timer;

    public bool Attached => _form.Attached;
    public double Scale => _form.Scale;

    public TaskbarBadge()
    {
        _form = new BadgeForm(this);
        _form.Show();
        _form.Reposition(); // 立即定位，确保 App 启动时 Attached 已就绪
        _timer = new WinForms.Timer { Interval = 800 };
        _timer.Tick += (_, _) => _form.Reposition();
        _timer.Start();
        Strings.LanguageChanged += () => _form.RebuildMenu();
    }

    public void UpdateStatus(PowerReading reading)
    {
        var watts = reading.TotalWatts;
        _form.SetText(watts is { } value ? $"{(int)Math.Round(value)} W" : "— W");
    }

    public Rect? Anchor() => _form.Attached ? _form.ScreenRect() : null;

    public void Dispose()
    {
        _timer.Stop();
        _timer.Dispose();
        _form.Dispose();
    }

    private sealed class BadgeForm : WinForms.Form
    {
        private readonly TaskbarBadge _owner;
        private string _text = "— W";
        private Font _numFont = new("Segoe UI Semibold", 15f, System.Drawing.FontStyle.Regular, GraphicsUnit.Pixel);
        private Font _unitFont = new("Segoe UI", 11f, System.Drawing.FontStyle.Regular, GraphicsUnit.Pixel);
        private int _numPx;
        private string _layoutNumber = "—", _layoutUnit = "W";
        private float _numberX, _numberTop, _unitX, _unitTop, _barX, _barStartY, _barEndY;
        private int _barPx = 4;
        private WinForms.ContextMenuStrip? _menu;
        private IntPtr _taskbar;

        public bool Attached { get; private set; }
        public double Scale { get; private set; } = 1.0;

        public BadgeForm(TaskbarBadge owner)
        {
            _owner = owner;
            FormBorderStyle = WinForms.FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = WinForms.FormStartPosition.Manual;
            TopMost = true;
            Bounds = new Rectangle(-32000, -32000, 60, 30);
            RebuildMenu();
        }

        protected override WinForms.CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                // WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED：不进 Alt+Tab、不抢焦点、逐像素透明
                cp.ExStyle |= 0x80 | 0x08000000 | 0x80000;
                return cp;
            }
        }

        public void SetText(string text)
        {
            if (_text == text) return;
            _text = text;
            Reposition();
        }

        public void RebuildMenu()
        {
            _menu?.Dispose();
            _menu = new WinForms.ContextMenuStrip();
            _menu.Items.Add(Strings.T("设置"), null, (_, _) => _owner.OpenSettings?.Invoke());
            _menu.Items.Add(new WinForms.ToolStripSeparator());
            _menu.Items.Add(Strings.T("退出 WattLite"), null, (_, _) => System.Windows.Application.Current.Shutdown());
        }

        public void Reposition()
        {
            var taskbar = FindWindow("Shell_TrayWnd", null);
            if (taskbar == IntPtr.Zero) { Attached = false; return; }
            _taskbar = taskbar;
            if (!GetWindowRect(taskbar, out var bar)) { Attached = false; return; }
            Attached = true;
            Scale = MonitorScale(bar.L + (bar.R - bar.L) / 2, bar.T + (bar.B - bar.T) / 2);

            // 全屏应用（视频/游戏）盖住任务栏时隐藏徽标，任务栏回来再显示
            if (FullscreenCoversTaskbar(bar))
            {
                SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0,
                    SwpNoActivate | SwpHideWindow | SwpNoSize | SwpNoMove);
                return;
            }

            // 锚点：托盘通知区左缘；找不到就退到任务栏右端
            var tray = FindWindowEx(taskbar, IntPtr.Zero, "TrayNotifyWnd", null);
            int anchorLeft, anchorTop;
            if (tray != IntPtr.Zero && GetWindowRect(tray, out var t)) { anchorLeft = t.L; anchorTop = t.T; }
            else { anchorLeft = bar.R; anchorTop = bar.T; }

            var barW = bar.R - bar.L;
            var barH = bar.B - bar.T;
            var numPx = Math.Min(32, Math.Max(13, (int)(barH * 0.39)));
            var unitPx = Math.Max(10, (int)Math.Round(numPx * 0.70));
            if (numPx != _numPx)
            {
                _numFont.Dispose();
                _unitFont.Dispose();
                _numFont = new Font("Segoe UI Semibold", numPx, System.Drawing.FontStyle.Regular, GraphicsUnit.Pixel);
                _unitFont = new Font("Segoe UI", unitPx, System.Drawing.FontStyle.Regular, GraphicsUnit.Pixel);
                _numPx = numPx;
            }

            var trimmed = _text.Trim();
            var split = trimmed.LastIndexOf(' ');
            _layoutNumber = split > 0 ? trimmed[..split] : trimmed;
            _layoutUnit = split > 0 ? trimmed[(split + 1)..] : "";

            // 用与绘制一致的 GDI+ 度量排版；色条 + 数字 + 小号单位，整体紧凑
            using var measureBmp = new Bitmap(1, 1);
            using var mg = Graphics.FromImage(measureBmp);
            mg.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            using var sf = (StringFormat)StringFormat.GenericTypographic.Clone();
            sf.FormatFlags |= StringFormatFlags.NoWrap;
            var numSize = mg.MeasureString(_layoutNumber, _numFont, PointF.Empty, sf);
            var unitSize = _layoutUnit.Length > 0
                ? mg.MeasureString(_layoutUnit, _unitFont, PointF.Empty, sf)
                : SizeF.Empty;

            var scale = Math.Max(1.0, Scale);
            var pad = (int)Math.Round(7 * scale);
            _barPx = Math.Max(2, (int)Math.Round(2 * scale));
            var barGap = (int)Math.Round(6 * scale);
            var unitGap = _layoutUnit.Length > 0 ? Math.Max(1, (int)Math.Round(3 * scale)) : 0;
            var w = pad + _barPx + barGap + (int)Math.Ceiling(numSize.Width) + unitGap +
                    (int)Math.Ceiling(unitSize.Width) + pad;
            var h = barH;

            var barHeight = 16 * scale;
            _barX = pad + _barPx / 2f;
            _barStartY = (float)((h - barHeight) / 2 + _barPx / 2.0);
            _barEndY = (float)(h - (h - barHeight) / 2 - _barPx / 2.0);

            _numberX = pad + _barPx + barGap;
            _numberTop = (h - numSize.Height) / 2f;
            var baseline = _numberTop + AscentPixels(_numFont);
            _unitX = _numberX + numSize.Width + unitGap;
            _unitTop = baseline - AscentPixels(_unitFont);

            int x, y;
            if (barW >= barH)
            {
                x = anchorLeft - w - 10;
                y = bar.T;
            }
            else
            {
                x = bar.L + (barW - w) / 2;
                y = anchorTop - h - 10;
            }
            // Win11 任务栏会周期性把自己重新置顶压住本窗，必须每 tick 主动压回
            SetWindowPos(Handle, new IntPtr(-1), x, y, w, h, SwpNoActivate | SwpShowWindow);
            _renderCount++;
            if (_renderCount <= 3) DebugLog($"Reposition #{_renderCount} set at ({x},{y}) {w}x{h} ulwPending");
            Render();
        }

        private int _renderCount;

        // 前台窗口完整盖住任务栏矩形 = 全屏（最大化窗口的工作区不含任务栏，不会误判）
        private bool FullscreenCoversTaskbar(in RECT bar)
        {
            var fg = GetForegroundWindow();
            if (fg == IntPtr.Zero || fg == Handle || fg == _taskbar) return false;
            var cls = new System.Text.StringBuilder(64);
            GetClassName(fg, cls, 64);
            var name = cls.ToString();
            if (name is "Progman" or "WorkerW" or "Shell_TrayWnd") return false;
            if (!GetWindowRect(fg, out var fr)) return false;
            return fr.L <= bar.L && fr.T <= bar.T && fr.R >= bar.R && fr.B >= bar.B;
        }

        // UpdateLayeredWindow 逐像素 Alpha：背景真透明（亚克力任务栏无需配色）、文字抗锯齿无毛边
        private void Render()
        {
            var w = Width;
            var h = Height;
            if (w <= 0 || h <= 0) return;
            using var bmp = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                // 背景 alpha=1：肉眼不可见但保留整卡点击命中（alpha=0 的像素点击穿透）
                using (var back = new SolidBrush(Color.FromArgb(1, 0, 0, 0)))
                    g.FillRectangle(back, 0, 0, w, h);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                // 任务栏可能是浅色亚克力：文字与色条跟随 Windows 任务栏明暗
                var light = TaskbarIsLight();
                var textColor = light ? Color.FromArgb(235, 24, 24, 26) : Color.FromArgb(245, 245, 245, 247);
                var unitColor = light ? Color.FromArgb(150, 24, 24, 26) : Color.FromArgb(165, 245, 245, 247);
                var accentColor = light ? Color.FromArgb(235, 11, 138, 138) : Color.FromArgb(235, 64, 192, 192);

                // 细圆头色条作品牌/实时标记，替代原来的光晕圆点
                if (_barEndY > _barStartY)
                {
                    using var accent = new Pen(accentColor, _barPx) { StartCap = LineCap.Round, EndCap = LineCap.Round };
                    g.DrawLine(accent, _barX, _barStartY, _barX, _barEndY);
                }

                using var sf = (StringFormat)StringFormat.GenericTypographic.Clone();
                sf.FormatFlags |= StringFormatFlags.NoWrap;
                using (var numberBrush = new SolidBrush(textColor))
                    g.DrawString(_layoutNumber, _numFont, numberBrush, _numberX, _numberTop, sf);
                if (_layoutUnit.Length > 0)
                {
                    using var unitBrush = new SolidBrush(unitColor);
                    g.DrawString(_layoutUnit, _unitFont, unitBrush, _unitX, _unitTop, sf);
                }
            }
            GetWindowRect(Handle, out var wr);
            var dst = new System.Drawing.Point(wr.L, wr.T);
            var src = new System.Drawing.Point(0, 0);
            var size = new System.Drawing.Size(w, h);
            var blend = new BLENDFUNCTION { BlendOp = 0, SourceConstantAlpha = 255, AlphaFormat = 1 };

            // GetHbitmap+CompatibleDC 是 ULW 的标准姿势：Graphics.GetHdc() 的 DC 不能被 ULW 采用
            var screenDc = GetDC(IntPtr.Zero);
            var memDc = CreateCompatibleDC(screenDc);
            var hBitmap = IntPtr.Zero;
            var oldBitmap = IntPtr.Zero;
            try
            {
                hBitmap = bmp.GetHbitmap(Color.FromArgb(0));
                oldBitmap = SelectObject(memDc, hBitmap);
                var ok = UpdateLayeredWindow(Handle, screenDc, ref dst, ref size, memDc, ref src, 0, ref blend, UlwAlpha);
                if (_renderCount <= 3 || !ok)
                {
                    var data = bmp.LockBits(new Rectangle(0, 0, w, h),
                        System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                    int opaque = 0, anyAlpha = 0;
                    unsafe
                    {
                        var row = (byte*)data.Scan0;
                        for (var y2 = 0; y2 < h; y2++)
                        {
                            var p = row + y2 * data.Stride;
                            for (var x2 = 0; x2 < w; x2++)
                            {
                                if (p[x2 * 4 + 3] != 0) anyAlpha++;
                                if (p[x2 * 4 + 3] == 255) opaque++;
                            }
                        }
                    }
                    bmp.UnlockBits(data);
                    DebugLog($"ULW ok={ok} err={Marshal.GetLastWin32Error()} size={w}x{h} opaquePx={opaque} anyAlphaPx={anyAlpha}");
                }
            }
            finally
            {
                if (oldBitmap != IntPtr.Zero) SelectObject(memDc, oldBitmap);
                if (hBitmap != IntPtr.Zero) DeleteObject(hBitmap);
                DeleteDC(memDc);
                ReleaseDC(IntPtr.Zero, screenDc);
            }
        }

        public System.Windows.Rect ScreenRect()
        {
            GetWindowRect(Handle, out var r);
            return new System.Windows.Rect(r.L, r.T, r.R - r.L, r.B - r.T);
        }

        private static float AscentPixels(Font font) =>
            font.FontFamily.GetCellAscent(font.Style) * font.Size / font.FontFamily.GetEmHeight(font.Style);

        // 任务栏明暗由系统主题决定（与面板手动明暗无关）：浅色任务栏用深色文字
        private static bool TaskbarIsLight()
        {
            try
            {
                return Microsoft.Win32.Registry.GetValue(
                    @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                    "SystemUsesLightTheme", 0) is int value && value != 0;
            }
            catch { return false; }
        }

        protected override void OnMouseUp(WinForms.MouseEventArgs e)
        {
            DebugLog($"OnMouseUp button={e.Button} at {e.X},{e.Y}");
            if (e.Button == WinForms.MouseButtons.Left) _owner.TogglePanel?.Invoke();
            else if (e.Button == WinForms.MouseButtons.Right) _menu?.Show(WinForms.Cursor.Position);
            base.OnMouseUp(e);
        }

        private static void DebugLog(string message) =>
            System.IO.File.AppendAllText(
                System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WattLite", "debug.log"),
                $"{DateTime.Now:HH:mm:ss.fff} {message}\n");

        // 像素由 UpdateLayeredWindow 提供，WM_PAINT 留空
        protected override void OnPaintBackground(WinForms.PaintEventArgs e) { }
        protected override void OnPaint(WinForms.PaintEventArgs e) { }

        protected override void WndProc(ref WinForms.Message m)
        {
            const int wmDisplayChange = 0x007E, wmDpiChanged = 0x02E0;
            if (m.Msg == wmDisplayChange || m.Msg == wmDpiChanged) Reposition();
            base.WndProc(ref m);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _menu?.Dispose();
                _numFont.Dispose();
                _unitFont.Dispose();
            }
            base.Dispose(disposing);
        }

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);

        private const uint SwpNoActivate = 0x0010, SwpShowWindow = 0x0040, SwpNoSize = 0x0001, SwpNoMove = 0x0002, SwpHideWindow = 0x0080;

        [DllImport("user32.dll")]
        private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref System.Drawing.Point pptDst,
            ref System.Drawing.Size psize, IntPtr hdcSrc, ref System.Drawing.Point pprSrc, uint crKey,
            ref BLENDFUNCTION pblend, uint dwFlags);

        private const uint UlwAlpha = 2;

        [StructLayout(LayoutKind.Sequential)]
        private struct BLENDFUNCTION
        {
            public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr hwnd, System.Text.StringBuilder name, int maxCount);

        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr hwnd);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteDC(IntPtr hdc);

        [DllImport("gdi32.dll")]
        private static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr obj);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr FindWindow(string className, string? windowName);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string? windowName);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hwnd);

        [DllImport("Shcore.dll")]
        private static extern int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromPoint(POINT pt, uint flags);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int X, Y;
        }

        // GetDpiForWindow 对系统窗口不可靠，按物理点所在显示器查有效 DPI
        private static double MonitorScale(int x, int y)
        {
            try
            {
                var pt = new POINT { X = x, Y = y };
                var monitor = MonitorFromPoint(pt, 0); // MONITOR_DEFAULTTONULL
                if (monitor != IntPtr.Zero && GetDpiForMonitor(monitor, 0, out var x1, out var _) == 0)
                    return x1 / 96.0;
            }
            catch { }
            return 1.0;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int L, T, R, B;
        }
    }
}
