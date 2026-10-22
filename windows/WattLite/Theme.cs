using System.Windows;
using System.Windows.Media;

namespace WattLite;

// 面板明暗主题：XAML 全部走 DynamicResource，切换时只改共享 Brush 的 Color
public static class Theme
{
    public static bool IsDark { get; private set; } = true;
    public static event Action? Changed;

    private static readonly Dictionary<string, Color> Dark = new()
    {
        ["Accent"] = Hex(0x40C0C0),
        ["AccentDim"] = Hex(0x294444),
        ["Surface"] = Hex(0x1E1E20),
        ["Canvas"] = Hex(0x28282A),
        ["Primary"] = Hex(0xF0F0F0),
        ["Secondary"] = Hex(0x9A9AA0),
        ["Popup"] = Hex(0x2E2E30),
        ["Hover"] = Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF),
        ["SegmentHover"] = Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF),
        ["GridLine"] = Color.FromArgb(0x26, 0x9A, 0x9A, 0xA0),
        ["WindowBorder"] = Color.FromArgb(0x00, 0x00, 0x00, 0x00),
        ["BadgeTint"] = Color.FromArgb(0x24, 0x38, 0x38, 0x38),
    };

    private static readonly Dictionary<string, Color> Light = new()
    {
        ["Accent"] = Hex(0x0B8A8A),
        ["AccentDim"] = Hex(0xD9ECEC),
        ["Surface"] = Hex(0xFFFFFF),
        ["Canvas"] = Hex(0xF2F2F4),
        ["Primary"] = Hex(0x1C1C1E),
        ["Secondary"] = Hex(0x6B6B73),
        ["Popup"] = Hex(0xFFFFFF),
        ["Hover"] = Color.FromArgb(0x14, 0x00, 0x00, 0x00),
        ["SegmentHover"] = Color.FromArgb(0x0F, 0x00, 0x00, 0x00),
        ["GridLine"] = Color.FromArgb(0x24, 0x6B, 0x6B, 0x73),
        ["WindowBorder"] = Hex(0xE0E0E5),
        ["BadgeTint"] = Color.FromArgb(0x0F, 0x00, 0x00, 0x00),
    };

    public static void Apply(string mode)
    {
        IsDark = mode != "light";
        var resources = System.Windows.Application.Current?.Resources;
        if (resources is null) return;
        foreach (var (key, color) in IsDark ? Dark : Light)
        {
            if (resources[key] is SolidColorBrush brush && !brush.IsFrozen)
                brush.Color = color;
            else
                resources[key] = new SolidColorBrush(color);
        }
        Changed?.Invoke();
    }

    public static void Set(string mode)
    {
        Settings.Current.Theme = mode == "light" ? "light" : "dark";
        Settings.Save();
        Apply(Settings.Current.Theme);
    }

    public static Color AccentColor => IsDark ? Hex(0x40C0C0) : Hex(0x0B8A8A);

    private static Color Hex(int rgb) =>
        Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
}
