using System.Diagnostics;
using System.Globalization;
using System.IO;

namespace WattLite;

public static class NvidiaSmi
{
    public sealed record GpuSample(string? Name, double? DrawWatts, double? LimitWatts, double? TempC, long? VramMiB);

    private const string Query =
        "--query-gpu=name,power.draw,power.limit,temperature.gpu,memory.total --format=csv,noheader,nounits";

    public static string? ExecutablePath { get; private set; }

    public static void Discover()
    {
        ExecutablePath = SearchPath() ?? FallbackPath();
    }

    private static string? SearchPath()
    {
        var pathVar = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(pathVar)) return null;
        foreach (var raw in pathVar.Split(';'))
        {
            var dir = raw.Trim().Trim('"');
            if (dir.Length == 0) continue;
            try
            {
                var candidate = Path.Combine(dir, "nvidia-smi.exe");
                if (File.Exists(candidate)) return candidate;
            }
            catch { }
        }
        return null;
    }

    private static string? FallbackPath()
    {
        try
        {
            var candidate = Path.Combine(Environment.SystemDirectory, "nvidia-smi.exe");
            return File.Exists(candidate) ? candidate : null;
        }
        catch { return null; }
    }

    public static async Task<GpuSample?> ReadAsync()
    {
        if (ExecutablePath is null) return null;
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = ExecutablePath,
                Arguments = Query,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            });
            if (process is null) return null;
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            var output = await process.StandardOutput.ReadToEndAsync(timeout.Token).ConfigureAwait(false);
            if (!timeout.Token.IsCancellationRequested)
                return ParseOutput(output);
        }
        catch { }
        return null;
    }

    // 多 GPU 取第一个非空行；解析容错：N/A、[N/A]、空行
    public static GpuSample? ParseOutput(string output)
    {
        foreach (var line in output.Split('\n'))
            if (!string.IsNullOrWhiteSpace(line))
                return ParseLine(line);
        return null;
    }

    public static GpuSample? ParseLine(string? line)
    {
        if (line is null || string.IsNullOrWhiteSpace(line)) return null;
        var fields = line.Split(',');
        if (fields.Length < 4) return null;
        var name = fields[0].Trim();
        return new GpuSample(
            name.Length == 0 || name.Contains("N/A", StringComparison.OrdinalIgnoreCase) ? null : name,
            Number(fields[1], PowerReading.ValidateGpu),
            Number(fields[2], PowerReading.ValidateGpu),
            Number(fields[3], PowerReading.ValidateTemp),
            MiB(fields.Length > 4 ? fields[4] : null));
    }

    private static long? MiB(string? field)
    {
        if (field is null) return null;
        var text = field.Trim().Trim('[', ']', ' ');
        if (text.Length == 0 || text.Contains("N/A", StringComparison.OrdinalIgnoreCase)) return null;
        return long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) && value > 0
            ? value
            : null;
    }

    private static double? Number(string field, Func<double, double?> validate)
    {
        var text = field.Trim().Trim('[', ']', ' ');
        if (text.Length == 0 || text.Contains("N/A", StringComparison.OrdinalIgnoreCase)) return null;
        return double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
            ? validate(value)
            : null;
    }
}
