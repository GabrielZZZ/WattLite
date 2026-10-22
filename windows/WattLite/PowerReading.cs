using System.Globalization;

namespace WattLite;

public sealed record PowerReading
{
    public DateTime CapturedAt { get; init; } = DateTime.Now;
    public double? CpuWatts { get; init; }
    public double? GpuWatts { get; init; }
    public double? GpuLimitWatts { get; init; }
    public double? TemperatureC { get; init; }
    public string? CpuName { get; init; }
    public string? GpuName { get; init; }
    public long? VramMiB { get; init; }
    public string? Issue { get; init; }

    public double? TotalWatts => CpuWatts is { } cpu && GpuWatts is { } gpu
        ? cpu + gpu
        : CpuWatts ?? GpuWatts;

    public bool HasBothParts => CpuWatts.HasValue && GpuWatts.HasValue;

    public static PowerReading Unavailable(string issue) => new() { Issue = issue };

    public static string PowerText(double? value) =>
        value is { } v && !double.IsNaN(v) && !double.IsInfinity(v)
            ? string.Format(CultureInfo.InvariantCulture, "{0:F1}", Math.Abs(v) < 0.05 ? 0 : v)
            : "—";

    public static double? ValidateCpu(double v) => v is >= 0 and <= 300 ? v : null;
    public static double? ValidateGpu(double v) => v is >= 0 and <= 600 ? v : null;
    public static double? ValidateTemp(double v) => v is >= 0 and <= 110 ? v : null;
}

// 矩形积分（上次功率 × dt）；>30 s 的缺口（睡眠、采样中断）不计入
public sealed class SessionEnergy
{
    public double Wh { get; private set; }
    public double Seconds { get; private set; }
    private DateTime? _lastAt;

    public void Add(double watts, DateTime at)
    {
        if (_lastAt is { } last)
        {
            var dt = (at - last).TotalSeconds;
            if (dt > 0 && dt < 30)
            {
                Wh += watts * dt / 3600;
                Seconds += dt;
            }
        }
        _lastAt = at;
    }

    public void Reset()
    {
        Wh = 0;
        Seconds = 0;
        _lastAt = null;
    }

    public double? AverageWatts => Seconds > 0 ? Wh / (Seconds / 3600) : null;

    // 能量参照物：minWh 是档位下限，unitWh 是一格多少瓦时；取不超过当前能量的最高档，计数恒 ≥ 1
    public static readonly (double MinWh, double UnitWh, string Zh)[] References =
    {
        (0.122, 0.122, "🍌 ≈ {0:F1} 根香蕉"),
        (3.0, 3.0, "🔋 ≈ {0:F1} 节 5 号电池"),
        (9.0, 9.0, "💡 ≈ {0:F1} 小时 LED 灯"),
        (23.3, 23.3, "💧 ≈ {0:F1} 杯水烧开"),
        (60.0, 60.0, "📺 ≈ {0:F1} 小时电视"),
        (93.0, 93.0, "🫖 ≈ {0:F1} 升水烧开"),
        (250.0, 250.0, "💨 ≈ {0:F1} 次吹风机"),
        (1000.0, 1000.0, "⚡ ≈ {0:F1} 度电"),
        (3000.0, 150.0, "🚗 ≈ {0:F1} 公里电动车"),
    };

    public static (string Zh, double Count)? Comparison(double wh)
    {
        for (var i = References.Length - 1; i >= 0; i--)
            if (wh >= References[i].MinWh)
                return (References[i].Zh, wh / References[i].UnitWh);
        return null;
    }
}
