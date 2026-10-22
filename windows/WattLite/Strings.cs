namespace WattLite;

// 机制照抄 Mac 版 Strings.swift：中文原文就是键，英文是查表值，查不到回落原文
public static class Strings
{
    public static string Lang
    {
        get => Settings.Current.Lang;
        set => Settings.Current.Lang = value;
    }

    public static event Action? LanguageChanged;

    public static void SetLang(string lang)
    {
        if (Lang == lang) return;
        Lang = lang;
        Settings.Save();
        LanguageChanged?.Invoke();
    }

    public static string T(string zh) => Lang == "en" && En.TryGetValue(zh, out var en) ? en : zh;

    public static string TF(string zh, params object[] args) =>
        string.Format(System.Globalization.CultureInfo.InvariantCulture, T(zh), args);

    private static readonly Dictionary<string, string> En = new()
    {
        // 状态
        ["数据不可用"] = "Data unavailable",
        ["正在读取"] = "Reading…",
        ["唤醒后重新采样"] = "Resampling after wake",
        ["CPU + GPU 主要部件"] = "CPU + GPU main parts",
        ["仅 CPU 直读"] = "CPU only (live)",
        ["仅 GPU 直读"] = "GPU only (live)",
        ["实时读取"] = "Live",
        ["硬件直采"] = "Live hardware readout",
        // 问题
        ["未找到 nvidia-smi，GPU 数据不可用"] = "nvidia-smi not found; GPU data unavailable",
        ["GPU 数据不可用"] = "GPU data unavailable",
        ["CPU 功率需要管理员权限"] = "CPU power needs administrator",
        ["CPU 功率不可用"] = "CPU power unavailable",
        // 面板
        ["功率趋势"] = "Power trend",
        ["等待有效采样"] = "Waiting for samples",
        ["10 分钟前"] = "10 min ago",
        ["{0} W · 现在"] = "{0} W · now",
        ["CPU 功率"] = "CPU power",
        ["GPU 功率"] = "GPU power",
        ["GPU 功耗上限"] = "GPU power limit",
        ["GPU 温度"] = "GPU temperature",
        ["主要部件之和，不含主板、内存、硬盘与电源损耗。"] =
            "Sum of main parts; excludes board, memory, drives and PSU losses.",
        ["本机"] = "This machine",
        ["{0} 核 {1} 线程"] = "{0} cores · {1} threads",
        ["{0} GB 内存 · {1} 条"] = "{0} GB RAM · {1} sticks",
        // 硬件卡
        ["{0} GB 显存"] = "{0} GB VRAM",
        ["上限 {0} W"] = "limit {0} W",
        ["内存"] = "Memory",
        ["{0} 条 · {1}"] = "{0} sticks · {1}",
        ["单条 {0} GB"] = "{0} GB per stick",
        ["双通道"] = "dual channel",
        ["单通道"] = "single channel",
        ["已用 / 总内存"] = "Used / total",
        ["写入速度"] = "Write speed",
        ["未挂载"] = "Unmounted",
        ["硬盘"] = "Storage",
        ["{0} 块 · 共 {1} TB"] = "{0} drives · {1} TB total",
        ["内存与硬盘无功率传感器"] = "No power sensor for memory or drives",
        ["本地运行 · 无网络请求"] = "Runs locally · No network requests",
        ["返回功率面板"] = "Back to power panel",
        ["设置"] = "Settings",
        ["退出 WattLite"] = "Quit WattLite",
        ["功率数据说明"] = "About these readings",
        ["主数字为 CPU 封装功率 + GPU 功率之和，即整机主要耗电部件，不含主板、内存、硬盘与电源转换损耗，故标 ≈。\n\nCPU 功率由主板传感器直读（LibreHardwareMonitor + PawnIO 驱动）；GPU 功率为 NVML 硬件直采。两者均为硬件真值。\n\n仅单个部件可用时，主数字退化为该部件真值并去掉 ≈；数据不可用时不估造数值。"] =
            "The big number is CPU package power + GPU power — the machine's main power draws. It excludes the board, memory, drives and PSU conversion losses, hence the ≈ marker.\n\nCPU power comes straight from the motherboard sensor (LibreHardwareMonitor + PawnIO driver); GPU power is sampled by NVML. Both are hardware readings.\n\nWhen only one part is available, the number degrades to that part's true value and drops the ≈; missing data is never estimated.",
        // 会话能量
        ["本次会话能量"] = "Session energy",
        ["时长"] = "Duration",
        ["平均功率"] = "Average",
        ["{0} 小时 {1} 分"] = "{0}h {1}m",
        ["{0} 分"] = "{0} min",
        ["不足 1 分"] = "Under 1 min",
        ["时长 {0} · 平均 {1} W"] = "Duration {0} · avg {1} W",
        ["主要部件功率之和，参照物为量级估算。"] = "Sum of main parts; comparisons are order-of-magnitude estimates.",
        // 参照物（键由 SessionEnergy.References 动态给出）
        ["🍌 ≈ {0:F1} 根香蕉"] = "🍌 ≈ {0:F1} bananas",
        ["🔋 ≈ {0:F1} 节 5 号电池"] = "🔋 ≈ {0:F1} AA cells",
        ["💡 ≈ {0:F1} 小时 LED 灯"] = "💡 ≈ {0:F1} h LED bulb",
        ["💧 ≈ {0:F1} 杯水烧开"] = "💧 ≈ {0:F1} mugs boiled",
        ["📺 ≈ {0:F1} 小时电视"] = "📺 ≈ {0:F1} h of TV",
        ["🫖 ≈ {0:F1} 升水烧开"] = "🫖 ≈ {0:F1} L boiled",
        ["💨 ≈ {0:F1} 次吹风机"] = "💨 ≈ {0:F1} hair-dryer runs",
        ["⚡ ≈ {0:F1} 度电"] = "⚡ ≈ {0:F1} kWh",
        ["🚗 ≈ {0:F1} 公里电动车"] = "🚗 ≈ {0:F1} km by EV",
        // 设置
        ["保持轻巧。\n只看重要的功率。"] = "Stay light.\nOnly the power that matters.",
        ["明暗外观"] = "Appearance",
        ["深色"] = "Dark",
        ["浅色"] = "Light",
        ["手动选择面板配色，切换后立即生效。"] = "Choose the panel palette manually; applies instantly.",
        ["界面语言"] = "Interface language",
        ["切换后立即生效，无需重启。"] = "Applies instantly, no restart needed.",
        ["后台采样间隔"] = "Background sampling",
        ["1 秒"] = "1 s",
        ["2 秒"] = "2 s",
        ["5 秒"] = "5 s",
        ["面板展开时每秒读取；睡眠时停止采集。"] =
            "The panel reads once per second while open; sampling stops during sleep.",
        ["WattLite {0}\n只读功率数据，不控制任何硬件；历史按分钟聚合存本地 CSV，可随时删除。"] =
            "WattLite {0}\nReads power data only and never controls hardware. History is aggregated per minute into local CSV and can be deleted anytime.",
        // 托盘
        ["WattLite 功率监测"] = "WattLite power monitor",
        ["主要部件"] = "main parts",
        ["{0} W（主要部件）"] = "{0} W (main parts)",
        ["CPU {0} W"] = "CPU {0} W",
        ["GPU {0} W"] = "GPU {0} W",
        ["GPU 上限 {0} W · {1} °C"] = "GPU limit {0} W · {1} °C",
    };
}
