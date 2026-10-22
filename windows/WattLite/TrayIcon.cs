using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Runtime.InteropServices;
using WinForms = System.Windows.Forms;

namespace WattLite;

// 托盘图标：青色圆角方块 + 粗体功率数字，等宽字体固定列宽防抖（Mac 版 App.swift 同款手法）
public sealed class TrayIcon : IDisposable
{
    public Action? TogglePanel;
    public Action? OpenSettings;

    private const int SmCxSmIcon = 49;

    private readonly PowerStore _store;
    private readonly WinForms.NotifyIcon _icon;
    private Icon? _rendered;

    public TrayIcon(PowerStore store)
    {
        _store = store;
        var menu = new WinForms.ContextMenuStrip();
        menu.Items.Add(Strings.T("设置"), null, (_, _) => OpenSettings?.Invoke());
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add(Strings.T("退出 WattLite"), null, (_, _) => System.Windows.Application.Current.Shutdown());
        _icon = new WinForms.NotifyIcon
        {
            ContextMenuStrip = menu,
            Visible = true,
            Text = Strings.T("WattLite 功率监测"),
        };
        _icon.MouseClick += (_, e) =>
        {
            if (e.Button == WinForms.MouseButtons.Left)
                TogglePanel?.Invoke();
        };
        _icon.BalloonTipClicked += (_, _) => OpenSettings?.Invoke();
        Strings.LanguageChanged += () => UpdateStatus(_store.Latest);
    }

    public void ShowUpdateAvailable(string version, bool downloaded)
    {
        _icon.BalloonTipTitle = Strings.T(downloaded ? "更新已准备好" : "发现新版本");
        _icon.BalloonTipText = downloaded
            ? Strings.TF("v{0} 已下载，点击打开设置并重启更新。", version)
            : Strings.TF("v{0} 可用，点击打开设置下载。", version);
        _icon.BalloonTipIcon = WinForms.ToolTipIcon.Info;
        _icon.ShowBalloonTip(10000);
    }

    public void UpdateStatus(PowerReading reading)
    {
        var watts = reading.TotalWatts;
        var number = watts is { } value ? ((int)Math.Round(value)).ToString(CultureInfo.InvariantCulture) : null;

        var size = SmallIconSize();
        using var bitmap = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            using var bg = RoundedRect(g, size);
            using var teal = new SolidBrush(Color.FromArgb(64, 192, 192));
            g.FillPath(teal, bg);
            if (number is not null)
            {
                // 数字尽可能占满方块；字符越多字号越小
                var text = number.Length > 3 ? number : number.PadLeft(3, ' ');
                using var font = FitFont(g, text, size);
                var textSize = g.MeasureString(text, font);
                using var textBrush = new SolidBrush(Color.FromArgb(13, 27, 27));
                g.DrawString(text, font, textBrush,
                    (size - textSize.Width) / 2f, (size - textSize.Height) / 2f);
            }
            else
            {
                DrawBolt(g, size);
            }
        }

        var old = _rendered;
        _rendered = Icon.FromHandle(bitmap.GetHicon());
        _icon.Icon = _rendered;
        if (old is not null) DestroyIcon(old.Handle);

        _icon.Text = Tooltip(reading, watts);
    }

    private static GraphicsPath RoundedRect(Graphics g, int size)
    {
        var radius = size * 0.24f;
        var path = new GraphicsPath();
        path.AddArc(0, 0, radius * 2, radius * 2, 180, 90);
        path.AddArc(size - radius * 2, 0, radius * 2, radius * 2, 270, 90);
        path.AddArc(size - radius * 2, size - radius * 2, radius * 2, radius * 2, 0, 90);
        path.AddArc(0, size - radius * 2, radius * 2, radius * 2, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static Font FitFont(Graphics g, string text, int size)
    {
        var fontSize = size * 0.92f;
        while (fontSize > 4)
        {
            var font = new Font("Consolas", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
            if (g.MeasureString(text, font).Width <= size - 2) return font;
            font.Dispose();
            fontSize -= 0.5f;
        }
        return new Font("Consolas", 4, FontStyle.Bold, GraphicsUnit.Pixel);
    }

    private static void DrawBolt(Graphics g, int size)
    {
        var s = size * 0.72f;
        var points = new PointF[]
        {
            new(0.58f * s, 0.02f * s),
            new(0.20f * s, 0.56f * s),
            new(0.44f * s, 0.56f * s),
            new(0.36f * s, 0.98f * s),
            new(0.80f * s, 0.42f * s),
            new(0.54f * s, 0.42f * s),
        };
        using var path = new GraphicsPath();
        path.AddPolygon(points);
        using var brush = new SolidBrush(Color.FromArgb(235, 250, 250));
        var offset = (size - s) / 2f;
        g.TranslateTransform(offset, offset);
        g.FillPath(brush, path);
        g.ResetTransform();
    }

    private static string Tooltip(PowerReading reading, double? watts)
    {
        var lines = new List<string>
        {
            watts is { } value
                ? Strings.TF("{0} W（主要部件）", PowerReading.PowerText(value))
                : Strings.T("数据不可用"),
            Strings.TF("CPU {0} W", PowerReading.PowerText(reading.CpuWatts)),
            Strings.TF("GPU {0} W", PowerReading.PowerText(reading.GpuWatts)),
        };
        var gpuDetails = new List<string>();
        if (reading.GpuLimitWatts is { } limit)
            gpuDetails.Add(Strings.TF("上限 {0} W", PowerReading.PowerText(limit)));
        if (reading.TemperatureC is { } temp)
            gpuDetails.Add($"{PowerReading.PowerText(temp)} °C");
        if (gpuDetails.Count > 0)
            lines.Add("GPU " + string.Join(" · ", gpuDetails));
        var machine = new[] { reading.CpuName, reading.GpuName }.Where(n => !string.IsNullOrEmpty(n));
        if (machine.Any()) lines.Add(string.Join(" · ", machine));
        var text = string.Join("\n", lines);
        return text.Length > 127 ? text[..127] : text;
    }

    private static int SmallIconSize()
    {
        try
        {
            var size = GetSystemMetrics(SmCxSmIcon);
            return size >= 16 ? size : 16;
        }
        catch { return 16; }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
        if (_rendered is not null) DestroyIcon(_rendered.Handle);
    }
}
