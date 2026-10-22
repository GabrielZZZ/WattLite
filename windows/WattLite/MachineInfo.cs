using System.Management;

namespace WattLite;

public sealed class MachineInfo
{
    public string? CpuName { get; private set; }
    public int Cores { get; private set; }
    public int Threads { get; private set; }
    public string? GpuName { get; private set; }
    public long MemoryBytes { get; private set; }
    public int MemorySticks { get; private set; }
    public string? MemoryVendor { get; private set; }
    public int MemorySpeedMts { get; private set; }
    public long VramBytes { get; private set; }
    public List<DiskInfo> Disks { get; } = new();
    public List<MemoryModule> MemoryModules { get; } = new();

    public sealed record DiskInfo(string Model, long Bytes, int Index, IReadOnlyList<string> Letters);
    public sealed record MemoryModule(string? Vendor, long Bytes, int SpeedMts);

    public static MachineInfo Detect()
    {
        var info = new MachineInfo();
        try
        {
            using var cpu = new ManagementObjectSearcher("SELECT Name, NumberOfCores, NumberOfLogicalProcessors FROM Win32_Processor");
            foreach (var item in cpu.Get())
            {
                info.CpuName = item["Name"]?.ToString()?.Trim();
                info.Cores = Convert.ToInt32(item["NumberOfCores"]);
                info.Threads = Convert.ToInt32(item["NumberOfLogicalProcessors"]);
                break;
            }
        }
        catch { }
        try
        {
            using var gpu = new ManagementObjectSearcher("SELECT Name, AdapterRAM FROM Win32_VideoController");
            foreach (var item in gpu.Get())
            {
                var name = item["Name"]?.ToString()?.Trim();
                if (name is null || name.Length == 0 || name.Contains("Virtual", StringComparison.OrdinalIgnoreCase)) continue;
                info.GpuName = name;
                // AdapterRAM 是 uint32，>4GB 显存会溢出，仅作低容量回退
                if (item["AdapterRAM"] is { } ram)
                    info.VramBytes = Math.Max(info.VramBytes, Convert.ToInt64(ram) & 0xFFFFFFFFL);
                if (name.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase)) break;
            }
        }
        catch { }
        try
        {
            using var ram = new ManagementObjectSearcher("SELECT Capacity, Manufacturer, Speed FROM Win32_PhysicalMemory");
            long total = 0;
            var sticks = 0;
            string? vendor = null;
            foreach (var item in ram.Get())
            {
                var capacity = Convert.ToInt64(item["Capacity"]);
                var moduleVendor = Clean(item["Manufacturer"]?.ToString());
                var speed = item["Speed"] is { } s ? Convert.ToInt32(s) : 0;
                total += capacity;
                sticks++;
                vendor ??= moduleVendor;
                info.MemoryModules.Add(new MemoryModule(moduleVendor, capacity, speed));
                info.MemorySpeedMts = Math.Max(info.MemorySpeedMts, speed);
            }
            info.MemoryBytes = total;
            info.MemorySticks = sticks;
            info.MemoryVendor = vendor;
        }
        catch { }
        try
        {
            var lettersByDisk = DiskDriveLetters();
            using var disks = new ManagementObjectSearcher("SELECT Model, Size, Index FROM Win32_DiskDrive");
            foreach (var item in disks.Get())
            {
                var model = Clean(item["Model"]?.ToString());
                if (model is null || model.Length == 0) continue;
                var size = item["Size"] is { } s ? Convert.ToInt64(s) : 0;
                var index = item["Index"] is { } i ? Convert.ToInt32(i) : -1;
                var letters = lettersByDisk.TryGetValue(index, out var found) ? found : new List<string>();
                info.Disks.Add(new DiskInfo(model, size, index, letters));
            }
        }
        catch { }
        return info;
    }

    // 物理盘索引 → 盘符列表：分区表给出 DiskIndex，逻辑卷关联给出 DeviceID（C:, D:, …）
    private static Dictionary<int, List<string>> DiskDriveLetters()
    {
        var result = new Dictionary<int, List<string>>();
        var partitionDisk = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var partitions = new ManagementObjectSearcher("SELECT DeviceID, DiskIndex FROM Win32_DiskPartition");
            foreach (ManagementBaseObject partition in partitions.Get())
            {
                var id = partition["DeviceID"]?.ToString()?.Trim();
                if (id is not null) partitionDisk[id] = Convert.ToInt32(partition["DiskIndex"]);
            }
            using var links = new ManagementObjectSearcher("SELECT Antecedent, Dependent FROM Win32_LogicalDiskToPartition");
            foreach (ManagementBaseObject link in links.Get())
            {
                // Antecedent = 分区，Dependent = 逻辑卷
                var partitionId = Quoted(link["Antecedent"]?.ToString());
                var letter = Quoted(link["Dependent"]?.ToString());
                if (partitionId is null || letter is null) continue;
                if (!partitionDisk.TryGetValue(partitionId, out var index)) continue;
                if (!result.TryGetValue(index, out var letters))
                    result[index] = letters = new List<string>();
                if (!letters.Contains(letter)) letters.Add(letter);
            }
        }
        catch { }
        foreach (var letters in result.Values) letters.Sort(StringComparer.OrdinalIgnoreCase);
        return result;
    }

    // 从 CIM 路径里取 DeviceID="..." 的值
    private static string? Quoted(string? path)
    {
        if (path is null) return null;
        const string marker = "DeviceID=";
        var at = path.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (at < 0) return null;
        var start = path.IndexOf('"', at + marker.Length);
        if (start < 0) return null;
        var end = path.IndexOf('"', start + 1);
        return end > start ? path[(start + 1)..end] : null;
    }

    // WMI 型号里常见连续空格（"WDC  WDS100T2B0A"），统一压成单个
    private static string? Clean(string? value) =>
        value is null ? null : System.Text.RegularExpressions.Regex.Replace(value.Trim(), @"\s+", " ");

    public string Title => CpuName ?? Strings.T("本机");
}

public static class VendorBadge
{
    // 官方品牌色（simple-icons 收录值）；深色面板上过暗的颜色提亮一档
    public static readonly System.Windows.Media.Color AmdColor = System.Windows.Media.Color.FromRgb(0xED, 0x1C, 0x24);
    public static readonly System.Windows.Media.Color NvidiaColor = System.Windows.Media.Color.FromRgb(0x76, 0xB9, 0x00);
    public static readonly System.Windows.Media.Color IntelColor = System.Windows.Media.Color.FromRgb(0x00, 0x71, 0xC5);
    public static readonly System.Windows.Media.Color SamsungColor = System.Windows.Media.Color.FromRgb(0x3E, 0x6E, 0xF0); // 官方 #1428A0 过暗，提亮
    public static readonly System.Windows.Media.Color CorsairColor = System.Windows.Media.Color.FromRgb(0xE6, 0xE6, 0xE6); // 官方 #231F20 近黑，用其白色版标
    public static readonly System.Windows.Media.Color FallbackColor = System.Windows.Media.Color.FromRgb(0x9A, 0x9A, 0xA0);

    // 厂商名 → (徽标 path, 品牌色)；未收录的返回 null（调用方回退文字徽章）
    public static (string Path, System.Windows.Media.Color Color)? Logo(string? model) => model switch
    {
        null => null,
        _ when model.Contains("AMD", StringComparison.OrdinalIgnoreCase) => (VendorLogos.Amd, AmdColor),
        _ when model.Contains("Radeon", StringComparison.OrdinalIgnoreCase) => (VendorLogos.Amd, AmdColor),
        _ when model.Contains("Intel", StringComparison.OrdinalIgnoreCase) => (VendorLogos.Intel, IntelColor),
        _ when model.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase) => (VendorLogos.Nvidia, NvidiaColor),
        _ when model.Contains("GeForce", StringComparison.OrdinalIgnoreCase) => (VendorLogos.Nvidia, NvidiaColor),
        _ when model.Contains("Samsung", StringComparison.OrdinalIgnoreCase) => (VendorLogos.Samsung, SamsungColor),
        _ when model.Contains("Corsair", StringComparison.OrdinalIgnoreCase) => (VendorLogos.Corsair, CorsairColor),
        _ => null,
    };

    // 厂商彩色原图（Assets/vendors/raster，只裁透明留白，不重绘不换色）；
    // 未收录的返回 null，调用方回退单色 Path 或文字徽章
    public static string? RasterIcon(string? model) => model switch
    {
        null => null,
        _ when model.Contains("AMD", StringComparison.OrdinalIgnoreCase) => Pack(Theme.IsDark ? "amd" : "amd-black"),
        _ when model.Contains("Radeon", StringComparison.OrdinalIgnoreCase) => Pack(Theme.IsDark ? "amd" : "amd-black"),
        _ when model.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase) => Pack("nvidia"),
        _ when model.Contains("GeForce", StringComparison.OrdinalIgnoreCase) => Pack("nvidia"),
        _ when model.Contains("Intel", StringComparison.OrdinalIgnoreCase) => Pack("intel"),
        _ when model.Contains("Samsung", StringComparison.OrdinalIgnoreCase) => Pack("samsung"),
        _ when model.Contains("Corsair", StringComparison.OrdinalIgnoreCase) => Pack("corsair"),
        _ when model.Contains("WDC", StringComparison.OrdinalIgnoreCase) => Pack("western-digital"),
        _ when model.Contains("Western Digital", StringComparison.OrdinalIgnoreCase) => Pack("western-digital"),
        _ => null,
    };

    private static string Pack(string slug) => $"pack://application:,,,/WattLite;component/Assets/vendors/raster/{slug}.png";

    // 文字徽章也用品牌色（金士顿红/西数蓝等为公开品牌色）
    public static System.Windows.Media.Color TextColor(string? model) => model switch
    {
        null => FallbackColor,
        _ when model.Contains("AMD", StringComparison.OrdinalIgnoreCase) => AmdColor,
        _ when model.Contains("Radeon", StringComparison.OrdinalIgnoreCase) => AmdColor,
        _ when model.Contains("Intel", StringComparison.OrdinalIgnoreCase) => IntelColor,
        _ when model.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase) => NvidiaColor,
        _ when model.Contains("GeForce", StringComparison.OrdinalIgnoreCase) => NvidiaColor,
        _ when model.Contains("Samsung", StringComparison.OrdinalIgnoreCase) => SamsungColor,
        _ when model.Contains("Corsair", StringComparison.OrdinalIgnoreCase) => CorsairColor,
        _ when model.Contains("Kingston", StringComparison.OrdinalIgnoreCase) => System.Windows.Media.Color.FromRgb(0xE3, 0x1E, 0x24),
        _ when model.Contains("WDC", StringComparison.OrdinalIgnoreCase) => System.Windows.Media.Color.FromRgb(0x00, 0x87, 0xCE),
        _ when model.Contains("Western Digital", StringComparison.OrdinalIgnoreCase) => System.Windows.Media.Color.FromRgb(0x00, 0x87, 0xCE),
        _ when model.Contains("Seagate", StringComparison.OrdinalIgnoreCase) => System.Windows.Media.Color.FromRgb(0x6E, 0xB4, 0x3C),
        _ when model.Contains("Crucial", StringComparison.OrdinalIgnoreCase) => System.Windows.Media.Color.FromRgb(0xE2, 0x2E, 0x1F),
        _ when model.Contains("SK hynix", StringComparison.OrdinalIgnoreCase) => System.Windows.Media.Color.FromRgb(0xEA, 0x6A, 0x00),
        _ => FallbackColor,
    };

    // 短厂商标签（文字徽章 / 卡片右上角）
    public static string Label(string? model) => model switch
    {
        null => "",
        _ when model.Contains("AMD", StringComparison.OrdinalIgnoreCase) => "AMD",
        _ when model.Contains("Radeon", StringComparison.OrdinalIgnoreCase) => "AMD",
        _ when model.Contains("Intel", StringComparison.OrdinalIgnoreCase) => "Intel",
        _ when model.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase) => "NVIDIA",
        _ when model.Contains("GeForce", StringComparison.OrdinalIgnoreCase) => "NVIDIA",
        _ when model.Contains("Samsung", StringComparison.OrdinalIgnoreCase) => "Samsung",
        _ when model.Contains("Corsair", StringComparison.OrdinalIgnoreCase) => "Corsair",
        _ when model.Contains("Kingston", StringComparison.OrdinalIgnoreCase) => "Kingston",
        _ when model.Contains("WDC", StringComparison.OrdinalIgnoreCase) => "WD",
        _ when model.Contains("Western Digital", StringComparison.OrdinalIgnoreCase) => "WD",
        _ when model.Contains("Seagate", StringComparison.OrdinalIgnoreCase) => "Seagate",
        _ when model.Contains("Crucial", StringComparison.OrdinalIgnoreCase) => "Crucial",
        _ when model.Contains("SK hynix", StringComparison.OrdinalIgnoreCase) => "SK hynix",
        _ => model.Length <= 12 ? model : "",
    };
}
