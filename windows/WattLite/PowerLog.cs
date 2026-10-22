using System.Globalization;
using System.IO;

namespace WattLite;

// 分钟级聚合落盘：CSV 即导出格式，无数据库无上传，删目录即清空
public sealed class PowerLog
{
    public const string Header = "ts,cpu_w,gpu_w,temperature";

    public static string DirectoryPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WattLite", "history");

    private readonly List<double?> _cpu = new();
    private readonly List<double?> _gpu = new();
    private readonly List<double?> _temp = new();
    private long _bucketMinute = -1;

    public void Record(PowerReading reading)
    {
        var minute = (long)(reading.CapturedAt.ToUniversalTime() - DateTime.UnixEpoch).TotalMinutes;
        if (_bucketMinute >= 0 && minute != _bucketMinute)
            Flush();
        _bucketMinute = minute;
        _cpu.Add(reading.CpuWatts);
        _gpu.Add(reading.GpuWatts);
        _temp.Add(reading.TemperatureC);
    }

    public void Flush()
    {
        if (_bucketMinute < 0 || _cpu.Count == 0) return;
        var ts = _bucketMinute * 60;
        Append(FormatRow(ts, Average(_cpu), Average(_gpu), Average(_temp)), ts);
        _cpu.Clear();
        _gpu.Clear();
        _temp.Clear();
    }

    public static string FormatRow(long ts, double? cpu, double? gpu, double? temp) =>
        string.Join(",", ts, Field(cpu), Field(gpu), Field(temp));

    private static string Field(double? value) => value is { } v
        ? v.ToString("F2", CultureInfo.InvariantCulture)
        : "";

    private static double? Average(List<double?> samples)
    {
        var values = samples.Where(s => s.HasValue).Select(s => s!.Value).ToList();
        return values.Count == 0 ? null : values.Average();
    }

    public static (DateTime Ts, double? Cpu, double? Gpu, double? Temp)? ParseRow(string? line)
    {
        if (line is null) return null;
        var fields = line.Split(',');
        if (fields.Length != 4 || !long.TryParse(fields[0], out var ts)) return null;
        return (DateTimeOffset.FromUnixTimeSeconds(ts).LocalDateTime,
            Num(fields[1]), Num(fields[2]), Num(fields[3]));
    }

    private static double? Num(string field) =>
        double.TryParse(field, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ? value : null;

    private static void Append(string line, long ts)
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            var day = DateTimeOffset.FromUnixTimeSeconds(ts).LocalDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            var path = Path.Combine(DirectoryPath, day + ".csv");
            if (!File.Exists(path))
                File.WriteAllText(path, Header + "\n");
            File.AppendAllText(path, line + "\n");
        }
        catch { }
    }
}
