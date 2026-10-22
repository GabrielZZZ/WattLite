using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using WinForms = System.Windows.Forms;

namespace WattLite;

public partial class PanelWindow : Window
{
    private readonly PowerStore _store;
    private readonly DispatcherTimer _hideTimer;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly List<(double X, double Speed, double Radius, double Phase)> _particles = new();
    private bool _particlesRunning;
    private DateTime _deactivateGraceUntil;

    // 任务栏嵌入徽标的锚点（物理像素），用于把面板钉在徽标旁
    public Func<Rect?>? AnchorProvider;

    public PanelWindow(PowerStore store)
    {
        InitializeComponent();
        _store = store;
        // 点击托盘图标时面板先失焦（Deactivated 先于 MouseClick 触发），
        // 延迟隐藏给托盘点击留出取消窗口，否则"点托盘关面板"会被立即重开
        _hideTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        _hideTimer.Tick += (_, _) => { _hideTimer.Stop(); HidePanel(); };
        _store.OnReading += reading => Dispatcher.Invoke(() => UpdateView(reading));
        Strings.LanguageChanged += () => Dispatcher.Invoke(() => UpdateView(_store.Latest));
        Theme.Changed += OnThemeChanged;
        GenerateParticles();
        CompositionTarget.Rendering += RenderParticles;
        IsVisibleChanged += (_, _) => _particlesRunning = IsVisible;
        RefreshSettingsView();
        UpdateView(_store.Latest);
    }

    public void Toggle()
    {
        DebugLog($"Toggle IsVisible={IsVisible}");
        _hideTimer.Stop();
        if (IsVisible) HidePanel();
        else ShowPanel();
    }

    public void ShowSettings()
    {
        ShowPanel();
        SetSettingsVisible(true);
    }

    public void ShowPanel(bool startup = false)
    {
        if (startup)
            _deactivateGraceUntil = DateTime.UtcNow.AddSeconds(3);
        DebugLog($"SHOW startup={startup}");
        PrepareGeometry();
        SetSettingsVisible(false);
        _store.SetVisible(true);
        Show();
        Activate();
    }

    private static void DebugLog(string message) =>
        System.IO.File.AppendAllText(
            System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WattLite", "debug.log"),
            $"{DateTime.Now:HH:mm:ss.fff} {message}\n");

    private void HidePanel()
    {
        DebugLog("HIDE");
        Hide();
        _store.SetVisible(false);
    }

    // 远程桌面/切换缩放会改变 DPI：按锚点显示器的实时 DPI 重设窗口物理尺寸，
    // 否则窗口停留在旧 DPI 的像素尺寸，WPF 逻辑尺寸被压缩，内容溢出触发滚动。
    // 用固定设计尺寸而非 Width/Height：外部改过尺寸后 WPF 会把这两个属性更新成当前逻辑尺寸
    private const double PanelWidthDip = 380, PanelHeightDip = 840;

    private void PrepareGeometry()
    {
        var (anchorX, anchorY) = AnchorPoint();
        var scale = Math.Max(1.0, ScaleAt(anchorX, anchorY));
        var hwnd = new WindowInteropHelper(this).EnsureHandle();
        var area = WinForms.Screen.FromPoint(new System.Drawing.Point((int)anchorX, (int)anchorY)).WorkingArea;
        var width = (int)Math.Round(PanelWidthDip * scale);
        var height = (int)Math.Round(PanelHeightDip * scale);
        var gap = (int)Math.Round(8 * scale);
        var left = Math.Clamp((int)Math.Round(anchorX) - width - gap,
            area.Left, Math.Max(area.Left, area.Right - width - gap));
        var top = Math.Clamp((int)Math.Round(anchorY) - height - gap,
            area.Top, Math.Max(area.Top, area.Bottom - height - gap));
        SetWindowPos(hwnd, IntPtr.Zero, left, top, width, height, SwpNoZOrder | SwpNoActivate);
        DebugLog($"GEOMETRY scale={scale:F2} anchor=({anchorX:F0},{anchorY:F0}) rect=({left},{top},{width},{height})");
    }

    private (double X, double Y) AnchorPoint()
    {
        if (AnchorProvider?.Invoke() is { } anchor) return (anchor.Right, anchor.Top);
        var point = WinForms.Cursor.Position;
        return (point.X, point.Y);
    }

    private static double ScaleAt(double x, double y)
    {
        var monitor = MonitorFromPoint(new POINT { X = (int)x, Y = (int)y }, MonitorDefaultToNearest);
        return monitor != IntPtr.Zero && GetDpiForMonitor(monitor, MdtEffectiveDpi, out var dpiX, out _) == 0
            ? dpiX / 96.0
            : 1.0;
    }

    private void OnDeactivated(object sender, EventArgs e)
    {
        if (DateTime.UtcNow < _deactivateGraceUntil)
        {
            DebugLog("DEACTIVATE ignored");
            return;
        }
        DebugLog("DEACTIVATE");
        _hideTimer.Start();
    }

    private void OnGearClick(object sender, RoutedEventArgs e) => SetSettingsVisible(SettingsPane.Visibility != Visibility.Visible);

    private void OnQuitClick(object sender, RoutedEventArgs e) => System.Windows.Application.Current.Shutdown();

    private void OnInfoClick(object sender, RoutedEventArgs e)
    {
        InfoText.Text = Strings.T("主数字为 CPU 封装功率 + GPU 功率之和，即整机主要耗电部件，不含主板、内存、硬盘与电源转换损耗，故标 ≈。\n\nCPU 功率由主板传感器直读（LibreHardwareMonitor + PawnIO 驱动）；GPU 功率优先通过 NVIDIA NVML / nvidia-smi 读取，AMD 与 Intel 显卡通过 LibreHardwareMonitor 读取。两者均为硬件真值。\n\n仅单个部件可用时，主数字退化为该部件真值并去掉 ≈；数据不可用时不估造数值。");
        InfoPopup.IsOpen = true;
    }

    private void SetSettingsVisible(bool visible)
    {
        SettingsPane.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        // 两个视图互斥，窗口尺寸钉死 380×724 不变
        foreach (var child in ((Panel)SettingsPane.Parent).Children)
            if (child is ScrollViewer sv && !ReferenceEquals(sv, SettingsPane))
                sv.Visibility = visible ? Visibility.Collapsed : Visibility.Visible;
        GearButton.Content = visible ? "\uE72B" : "\uE713";
        UpdateStaticTexts();
        if (visible) RefreshSettingsView();
    }

    private void RefreshSettingsView()
    {
        var interval = _store.Interval;
        Seg1.Content = Strings.T("1 秒");
        Seg2.Content = Strings.T("2 秒");
        Seg5.Content = Strings.T("5 秒");
        Seg1.IsChecked = interval == 1;
        Seg2.IsChecked = interval == 2;
        Seg5.IsChecked = interval == 5;
        ThemeDark.Content = Strings.T("深色");
        ThemeLight.Content = Strings.T("浅色");
        ThemeDark.IsChecked = Theme.IsDark;
        ThemeLight.IsChecked = !Theme.IsDark;
        LangZh.IsChecked = Strings.Lang == "zh";
        LangEn.IsChecked = Strings.Lang == "en";
    }

    private void OnThemeClick(object sender, RoutedEventArgs e) =>
        Theme.Set(((RadioButton)sender) == ThemeLight ? "light" : "dark");

    // 主题切换后重建卡片（徽标底色随明暗变化），趋势与设置页同步重绘
    private void OnThemeChanged() => Dispatcher.Invoke(() =>
    {
        BuildHardwareCards();
        DrawTrend(_store.Latest);
        RefreshSettingsView();
    });

    private void OnLangClick(object sender, RoutedEventArgs e)
    {
        Strings.SetLang(((RadioButton)sender) == LangEn ? "en" : "zh");
        RefreshSettingsView();
        // 语言切换后让翻译在下一次渲染前生效（需先更新 FooterCaption 等静态文本）
        UpdateStaticTexts();
    }

    private void OnIntervalClick(object sender, RoutedEventArgs e)
    {
        _store.Interval = ((RadioButton)sender) == Seg1 ? 1 : ((RadioButton)sender) == Seg2 ? 2 : 5;
    }

    // 硬件卡右侧读数：CPU/GPU 功率、内存已用/总量、每块磁盘各自的写入速度
    private TextBlock? _cpuCardPower, _gpuCardPower, _ramCardValue;
    private readonly List<(int Index, TextBlock Block)> _diskCardValues = new();
    private string? _cardsLang;
    private MachineInfo? _cardsMachine;
    private string? _cardsGpuName;
    private bool _fitLogged;

    private void BuildHardwareCards()
    {
        var machine = _store.Machine;
        var cards = HardwareCards;
        cards.Children.Clear();
        _cpuCardPower = null;

        var cpuCard = Card(VendorBadge.Logo(machine?.CpuName), VendorBadge.Label(machine?.CpuName),
            machine?.CpuName ?? Strings.T("本机"),
            machine is { Cores: > 0 } ? Strings.TF("{0} 核 {1} 线程", machine.Cores, machine.Threads) : "",
            out var cpuPower, VendorBadge.RasterIcon(machine?.CpuName));
        _cpuCardPower = cpuPower;

        var gpuParams = new List<string>();
        // nvidia-smi 可用量略低于标称（16 GB 卡报 16303 MiB ≈ 15.92 GiB），四舍五入回标称值
        if (_store.Latest.VramMiB is { } vram) gpuParams.Add(Strings.TF("{0} GB 显存", (int)Math.Round(vram / 1024.0)));
        if (_store.Latest.GpuLimitWatts is { } limit) gpuParams.Add(Strings.TF("上限 {0} W", PowerReading.PowerText(limit)));
        var gpuName = _store.Latest.GpuName ?? machine?.GpuName;
        var gpuCard = Card(VendorBadge.Logo(gpuName), VendorBadge.Label(gpuName),
            gpuName ?? "—", string.Join(" · ", gpuParams), out var gpuPower, VendorBadge.RasterIcon(gpuName));
        _gpuCardPower = gpuPower;

        string ramTitle, ramParams;
        var ramDetails = new List<string>();
        if (machine is { MemoryBytes: > 0 })
        {
            ramTitle = $"{Strings.T("内存")} · {machine.MemoryBytes >> 30} GB";
            var channel = machine.MemorySticks >= 2 && machine.MemorySticks % 2 == 0 ? "双通道" : "单通道";
            var parts = new List<string> { Strings.TF("{0} 条 · {1}", machine.MemorySticks, Strings.T(channel)) };
            if (machine.MemorySpeedMts > 0) parts.Add($"DDR4-{machine.MemorySpeedMts}");
            ramParams = string.Join(" · ", parts);
            ramDetails.AddRange(DescribeMemory(machine));
        }
        else { ramTitle = Strings.T("内存"); ramParams = ""; }
        var ramCard = Card(VendorBadge.Logo(machine?.MemoryVendor), VendorBadge.Label(machine?.MemoryVendor),
            ramTitle, ramParams, out var ramValue, VendorBadge.RasterIcon(machine?.MemoryVendor),
            Strings.T("已用 / 总内存"), ramDetails);
        _ramCardValue = ramValue;

        cards.Children.Add(cpuCard);
        cards.Children.Add(gpuCard);
        cards.Children.Add(ramCard);

        // 每块盘一张独立卡：自己的厂商徽标、型号、容量与写入速度
        _diskCardValues.Clear();
        if (machine is { } m && m.Disks.Count > 0)
        {
            foreach (var disk in m.Disks.OrderByDescending(d => d.Bytes))
            {
                var model = disk.Model;
                var letters = disk.Letters.Count > 0
                    ? string.Join(" ", disk.Letters)
                    : Strings.T("未挂载");
                var diskCard = Card(VendorBadge.Logo(model), VendorBadge.Label(model),
                    model, $"{letters} · {disk.Bytes / 1e12:0.0} TB", out var diskValue,
                    VendorBadge.RasterIcon(model), Strings.T("写入速度"));
                _diskCardValues.Add((disk.Index, diskValue));
                cards.Children.Add(diskCard);
            }
        }
        else
        {
            cards.Children.Add(Card(null, "", Strings.T("硬盘"), "", out _,
                null, Strings.T("写入速度")));
        }
    }

    // 同型号内存合并为一条（Corsair 16 GB × 2），不同容量/厂商逐条列出
    private static IEnumerable<string> DescribeMemory(MachineInfo machine)
    {
        foreach (var group in machine.MemoryModules
                     .GroupBy(m => (Vendor: m.Vendor ?? "", m.Bytes))
                     .OrderByDescending(g => g.Key.Bytes))
        {
            var vendor = VendorBadge.Label(group.Key.Vendor);
            var name = vendor.Length > 0 ? vendor : group.Key.Vendor;
            var size = $"{group.Key.Bytes / 1073741824.0:0.#} GB";
            yield return $"{(name.Length > 0 ? name + " " : "")}{size}" +
                         (group.Count() > 1 ? $" × {group.Count()}" : "");
        }
    }

    // 徽标已表明厂商，标题去掉重复的厂商前缀，为长型号名腾出宽度
    private static string StripVendor(string title)
    {
        foreach (var vendor in new[] { "AMD ", "Intel ", "NVIDIA ", "Samsung ", "Corsair ", "WDC ", "Western Digital " })
            if (title.StartsWith(vendor, StringComparison.OrdinalIgnoreCase))
                return title[vendor.Length..];
        return title;
    }

    // 单张硬件卡：厂商彩色原图优先（按比例缩放，不重绘不换色），回退单色 Path，再回退文字徽章
    // details 用于同类多设备逐条列出；右侧读数可带一行小标签（已用/总内存、写入速度）
    private Border Card((string Path, System.Windows.Media.Color Color)? logo, string vendorLabel, string title, string parameters,
        out TextBlock value, string? rasterIcon = null, string? valueCaption = null, IReadOnlyList<string>? details = null)
    {
        var surface = (System.Windows.Media.Brush)FindResource("Surface");
        var primary = (System.Windows.Media.Brush)FindResource("Primary");
        var secondary = (System.Windows.Media.Brush)FindResource("Secondary");
        var brand = logo?.Color ?? VendorBadge.TextColor(vendorLabel);
        var badgeBackground = (System.Windows.Media.Brush)FindResource("BadgeTint");

        UIElement badge;
        if (rasterIcon is not null)
        {
            var image = new Image
            {
                Source = LoadRasterIcon(rasterIcon),
                Stretch = Stretch.Uniform,
                Margin = new Thickness(5),
            };
            RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
            badge = new Border
            {
                Width = 44, Height = 30, CornerRadius = new CornerRadius(7),
                Background = badgeBackground, Child = image,
            };
        }
        else if (logo is { } l)
        {
            badge = new Border
            {
                Width = 44, Height = 30, CornerRadius = new CornerRadius(7),
                Background = badgeBackground,
                Child = new System.Windows.Shapes.Path
                {
                    Data = System.Windows.Media.Geometry.Parse(l.Path),
                    Fill = new SolidColorBrush(brand), Stretch = Stretch.Uniform, Margin = new Thickness(6),
                },
            };
        }
        else
        {
            badge = new Border
            {
                Width = 44, Height = 30, CornerRadius = new CornerRadius(7),
                Background = badgeBackground,
                Child = new TextBlock
                {
                    Text = vendorLabel, FontSize = vendorLabel.Length > 6 ? 8 : 10,
                    FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(brand),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
            };
        }

        // Grid 而非 StackPanel：StackPanel 给子级无限宽度，TextTrimming 失效且无法占满剩余列宽；
        // 两行 RowDefinition 分别放标题与参数，缺了行定义会导致两行重叠渲染（重影）
        var texts = new Grid { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) };
        texts.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        texts.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var titleBlock = new TextBlock
        {
            Text = StripVendor(title), FontSize = 12, FontWeight = FontWeights.Medium,
            Foreground = primary, TextTrimming = TextTrimming.CharacterEllipsis,
        };
        var paramBlock = new TextBlock
        {
            Text = parameters, FontSize = 10, Foreground = secondary,
            Margin = new Thickness(0, 2, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis,
        };
        Grid.SetRow(titleBlock, 0);
        Grid.SetRow(paramBlock, 1);
        texts.Children.Add(titleBlock);
        texts.Children.Add(paramBlock);

        var valueBlock = new TextBlock
        {
            Text = "—", FontSize = 13, FontWeight = FontWeights.Medium, Foreground = primary,
            HorizontalAlignment = HorizontalAlignment.Right,
            Typography = { NumeralAlignment = FontNumeralAlignment.Tabular },
        };
        value = valueBlock;

        UIElement metric;
        if (valueCaption is null)
        {
            valueBlock.VerticalAlignment = VerticalAlignment.Center;
            valueBlock.Margin = new Thickness(8, 0, 0, 0);
            metric = valueBlock;
        }
        else
        {
            valueBlock.FontSize = 12;
            var stack = new StackPanel
            {
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(8, 0, 0, 0),
            };
            stack.Children.Add(valueBlock);
            stack.Children.Add(new TextBlock
            {
                Text = valueCaption, FontSize = 9, Foreground = secondary,
                HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 1, 0, 0),
            });
            metric = stack;
        }

        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(badge, 0);
        Grid.SetColumn(texts, 1);
        Grid.SetColumn(metric, 2);
        row.Children.Add(badge);
        row.Children.Add(texts);
        row.Children.Add(metric);

        var content = new StackPanel();
        content.Children.Add(row);
        if (details is { Count: > 0 })
        {
            // 与标题左对齐（徽章 44 + 间距 8），每条一台设备
            var list = new StackPanel { Margin = new Thickness(52, 3, 0, 0) };
            foreach (var line in details)
                list.Children.Add(new TextBlock
                {
                    Text = line, FontSize = 10, Foreground = secondary,
                    TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 1, 0, 1),
                });
            content.Children.Add(list);
        }

        return new Border
        {
            Background = surface, CornerRadius = new CornerRadius(12),
            Padding = new Thickness(8, 7, 8, 7), Margin = new Thickness(0, 0, 0, 5),
            Child = content,
        };
    }

    private static ImageSource LoadRasterIcon(string uri)
    {
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.UriSource = new Uri(uri, UriKind.Absolute);
        bitmap.CacheOption = BitmapCacheOption.OnLoad; // 同步解码，离屏渲染首帧也能取到
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }

    private void UpdateView(PowerReading reading)
    {
        var watts = reading.TotalWatts;
        var approximate = reading.HasBothParts;
        ApproxMark.Text = approximate ? "≈" : "";
        ApproxMark.ToolTip = approximate ? Strings.T("主要部件之和，不含主板、内存、硬盘与电源损耗。") : null;
        BigNumber.Text = PowerReading.PowerText(watts);
        StateText.Text = GetStateText(reading);
        LiveTag.Text = watts is null ? Strings.T("数据不可用") : Strings.T("实时读取");
        SubLine.Text = $"{Strings.T("CPU 功率")} {PowerReading.PowerText(reading.CpuWatts)} W · " +
                       $"{Strings.T("GPU 功率")} {PowerReading.PowerText(reading.GpuWatts)} W";

        CpuLabel.Text = Strings.T("CPU 功率");
        CpuValue.Text = WattsText(reading.CpuWatts);
        GpuLabel.Text = Strings.T("GPU 功率");
        GpuValue.Text = WattsText(reading.GpuWatts);
        LimitLabel.Text = Strings.T("GPU 功耗上限");
        LimitValue.Text = WattsText(reading.GpuLimitWatts);
        TempLabel.Text = Strings.T("GPU 温度");
        TempValue.Text = reading.TemperatureC is { } temp ? $"{PowerReading.PowerText(temp)} °C" : "—";

        // 硬件卡：语言切换或 Machine 异步检测结果到位时重建；功率值每帧刷新
        if (_cardsLang != Strings.Lang || _cpuCardPower is null ||
            _cardsMachine != _store.Machine || _cardsGpuName != _store.Latest.GpuName)
        {
            _cardsLang = Strings.Lang;
            _cardsMachine = _store.Machine;
            _cardsGpuName = _store.Latest.GpuName;
            BuildHardwareCards();
        }
        // 溢出测量：Extent > Viewport 说明内容超高、需要滚动
        if (MainScroll.ExtentHeight > MainScroll.ViewportHeight + 0.5)
            DebugLog($"OVERFLOW extent={MainScroll.ExtentHeight:F0} viewport={MainScroll.ViewportHeight:F0} delta={MainScroll.ExtentHeight - MainScroll.ViewportHeight:F0}");
        else if (!_fitLogged && MainScroll.ViewportHeight > 0)
        {
            _fitLogged = true;
            DebugLog($"FIT extent={MainScroll.ExtentHeight:F1} viewport={MainScroll.ViewportHeight:F1} slack={MainScroll.ViewportHeight - MainScroll.ExtentHeight:F1}");
        }
        if (_cpuCardPower is not null) _cpuCardPower.Text = WattsText(reading.CpuWatts);
        if (_gpuCardPower is not null) _gpuCardPower.Text = WattsText(reading.GpuWatts);

        if (_ramCardValue is not null)
        {
            var total = _store.Machine?.MemoryBytes ?? 0;
            _ramCardValue.Text = total > 0 && SystemMetrics.UsedPhysicalMemoryBytes() is { } used
                ? $"{used / 1073741824.0:0.0} / {total >> 30} GB"
                : "—";
        }
        if (_diskCardValues.Count > 0)
        {
            var speeds = SystemMetrics.DiskWriteSpeeds(_diskCardValues.Where(d => d.Index >= 0).Select(d => d.Index));
            foreach (var (index, block) in _diskCardValues)
                block.Text = SystemMetrics.SpeedText(
                    index >= 0 && speeds.TryGetValue(index, out var speed) ? speed : null);
        }

        var sub = new List<string>();
        if (reading.Issue is { } issue) sub.Add(Strings.T(issue));
        sub.Add(Strings.TF("时长 {0} · 平均 {1} W", DurationText(_store.Session.Seconds),
            _store.Session.AverageWatts is { } avg ? PowerReading.PowerText(avg) : "—"));
        if (SessionEnergy.Comparison(_store.Session.Wh) is { } comparison)
            sub.Add(Strings.TF(comparison.Zh, comparison.Count));
        SessionTitle.Text = Strings.T("本次会话能量");
        SessionWh.Text = string.Format(System.Globalization.CultureInfo.InvariantCulture, "{0:F1}", _store.Session.Wh);
        SessionSub.Text = string.Join(" · ", sub);

        DrawTrend(reading);
        UpdateStaticTexts();
    }

    private static string GetStateText(PowerReading reading) => reading.CpuWatts is not null && reading.GpuWatts is not null
        ? Strings.T("CPU + GPU 主要部件")
        : reading.CpuWatts is not null ? Strings.T("仅 CPU 直读")
        : reading.GpuWatts is not null ? Strings.T("仅 GPU 直读")
        : Strings.T(reading.Issue ?? "数据不可用");

    private static string WattsText(double? watts) =>
        watts is { } value ? PowerReading.PowerText(value) + " W" : "—";

    private static string DurationText(double seconds)
    {
        var minutes = (int)seconds / 60;
        return minutes >= 60 ? Strings.TF("{0} 小时 {1} 分", minutes / 60, minutes % 60)
            : minutes > 0 ? Strings.TF("{0} 分", minutes)
            : Strings.T("不足 1 分");
    }

    private void UpdateStaticTexts()
    {
        FooterCaption.Text = Strings.T("本地运行 · 无网络请求");
        TrendTitle.Text = Strings.T("功率趋势");
        TrendEmpty.Text = Strings.T("等待有效采样");
        TrendLeft.Text = Strings.T("10 分钟前");
        GearButton.ToolTip = Strings.T(SettingsPane.Visibility == Visibility.Visible ? "返回功率面板" : "设置");
        SettingsHeadline.Text = Strings.T("保持轻巧。\n只看重要的功率。");
        AppearanceHeadline.Text = Strings.T("明暗外观");
        AppearanceNote.Text = Strings.T("手动选择面板配色，切换后立即生效。");
        LangHeadline.Text = Strings.T("界面语言");
        LangNote.Text = Strings.T("切换后立即生效，无需重启。");
        IntervalHeadline.Text = Strings.T("后台采样间隔");
        IntervalNote.Text = Strings.T("面板展开时每秒读取；睡眠时停止采集。");
        VersionNote.Text = Strings.TF("WattLite {0}\n只读功率数据，不控制任何硬件；历史按分钟聚合存本地 CSV，可随时删除。",
            typeof(PanelWindow).Assembly.GetName().Version?.ToString(3) ?? "0.1.0");
        InfoButton.ToolTip = Strings.T("功率数据说明");
    }

    // 趋势：最近 10 分钟主数字折线 + 面积渐变 + 虚线基准（移植 TrendView.swift）
    private void DrawTrend(PowerReading reading)
    {
        var canvas = TrendCanvas;
        canvas.Children.Clear();
        var now = reading.CapturedAt;
        var samples = _store.History
            .Where(p => (now - p.At).TotalSeconds is >= 0 and <= 600)
            .OrderBy(p => p.At)
            .ToList();
        var width = canvas.ActualWidth > 0 ? canvas.ActualWidth : 344;
        var height = canvas.ActualHeight > 0 ? canvas.ActualHeight : 110;
        var pad = 3.0;
        var plotH = height - 2 * pad;

        var maxWatts = samples.Count > 0 ? samples.Max(p => p.Watts) : 0;
        var minWatts = samples.Count > 0 ? samples.Min(p => p.Watts) : 0;
        var upper = Math.Max(10, Math.Ceiling(maxWatts / 10) * 10);
        var lower = Math.Min(0, Math.Floor(minWatts / 10) * 10);
        TrendMax.Text = $"{(int)upper} W";
        TrendRight.Text = Strings.TF("{0} W · 现在", (int)lower);
        TrendEmpty.Visibility = samples.Count < 2 ? Visibility.Visible : Visibility.Collapsed;

        var accent = ((SolidColorBrush)FindResource("Accent")).Color;
        var grid = ((SolidColorBrush)FindResource("GridLine")).Color;
        var brush = new SolidColorBrush(accent);
        var dimBrush = new SolidColorBrush(Color.FromArgb(38, accent.R, accent.G, accent.B));
        for (var i = 0; i <= 2; i++)
        {
            var y = pad + plotH * i / 2;
            canvas.Children.Add(new Line
            {
                X1 = 0, X2 = width, Y1 = y, Y2 = y,
                StrokeThickness = 0.5,
                Stroke = new SolidColorBrush(grid),
                StrokeDashArray = new DoubleCollection { 3, 4 },
            });
        }

        var gapTolerance = Math.Max(5, _store.Interval * 3);
        var points = new List<Point>();
        var segments = new List<List<Point>> { new() };
        DateTime? previous = null;
        foreach (var (at, value) in samples)
        {
            var x = width * (1 - (now - at).TotalSeconds / 600);
            var y = pad + plotH * (1 - (value - lower) / (upper - lower));
            var point = new Point(x, y);
            if (previous is { } prev && (at - prev).TotalSeconds > gapTolerance)
                segments.Add(new());
            segments[^1].Add(point);
            points.Add(point);
            previous = at;
        }

        if (points.Count >= 2)
        {
            var first = points[0].X;
            var last = points[^1].X;
            var areaPoints = new List<Point>(points)
            {
                new(last, pad + plotH),
                new(first, pad + plotH),
            };
            var area = new Polygon
            {
                Points = new PointCollection(areaPoints),
                Fill = dimBrush,
            };
            canvas.Children.Add(area);
            foreach (var segment in segments.Where(s => s.Count >= 2))
            {
                var line = new Polyline
                {
                    Points = new PointCollection(segment),
                    Stroke = brush,
                    StrokeThickness = 1.8,
                    StrokeLineJoin = PenLineJoin.Round,
                    StrokeEndLineCap = PenLineCap.Round,
                    StrokeStartLineCap = PenLineCap.Round,
                };
                canvas.Children.Add(line);
            }
        }
    }

    // 粒子场（v1 简化）：功率越高上升越快，密度与亮度随功率增长
    private void GenerateParticles()
    {
        for (var i = 0; i < 26; i++)
        {
            _particles.Add((0.03 + 0.94 * Hash(i, 6), 14 + 30 * Hash(i, 3),
                1.2 + 1.6 * Hash(i, 4), Hash(i, 8)));
        }
    }

    private void RenderParticles(object? sender, EventArgs e)
    {
        if (!_particlesRunning || ParticleCanvas.ActualWidth < 10) return;
        var canvas = ParticleCanvas;
        canvas.Children.Clear();
        var width = canvas.ActualWidth;
        var height = canvas.ActualHeight;
        var watts = _store.Latest.TotalWatts ?? 0;
        var intensity = Math.Min(1, watts / 300);
        var t = _clock.Elapsed.TotalSeconds;
        var accent = ((SolidColorBrush)FindResource("Accent")).Color;
        foreach (var (x, speed, radius, phase) in _particles)
        {
            var velocity = speed * (0.5 + intensity);
            var span = height * 0.94;
            var y = height * 1.02 - (t * velocity + phase * span) % span;
            var progress = y / height;
            var fade = Math.Min(1, Math.Max(0, (progress - 0.25) / 0.38))
                     * Math.Min(1, Math.Max(0, (1.02 - progress) / 0.10));
            var alpha = (0.55 + 0.29 * phase) * fade;
            if (alpha < 0.02) continue;
            var dot = new Ellipse
            {
                Width = radius * 2,
                Height = radius * 2,
                Fill = new SolidColorBrush(Color.FromArgb(
                    (byte)(alpha * 255 * (0.3 + 0.5 * intensity)), accent.R, accent.G, accent.B)),
            };
            Canvas.SetLeft(dot, width * x);
            Canvas.SetTop(dot, y);
            canvas.Children.Add(dot);
        }
    }

    private static double Hash(int i, int salt)
    {
        var v = Math.Sin(i + 1 + salt * 311.7) * 43758.5453;
        return v - Math.Floor(v);
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        if (PresentationSource.FromVisual(this) is HwndSource source)
            source.AddHook(WndProc);
    }

    // 缩放/分辨率在窗口存活期间变化（含 RDP 重连）时重新校准尺寸与位置
    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg is WmDpiChanged or WmDisplayChange && IsVisible)
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () =>
            {
                if (IsVisible) PrepareGeometry();
            });
        return IntPtr.Zero;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(POINT point, uint flags);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    private const uint MonitorDefaultToNearest = 2;
    private const int MdtEffectiveDpi = 0;
    private const uint SwpNoZOrder = 0x0004, SwpNoActivate = 0x0010;
    private const int WmDisplayChange = 0x007E, WmDpiChanged = 0x02E0;

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        CompositionTarget.Rendering -= RenderParticles;
        base.OnClosing(e);
    }
}
