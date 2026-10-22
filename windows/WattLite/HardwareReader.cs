using LibreHardwareMonitor.Hardware;

namespace WattLite;

public sealed class HardwareReader : IDisposable
{
    public sealed record GpuRead(string? Name, double? Watts, double? TempC, long? VramMiB);

    private Computer? _computer;
    private IHardware? _cpu;
    private IHardware? _gpu;

    public static bool IsAdmin =>
        new System.Security.Principal.WindowsPrincipal(System.Security.Principal.WindowsIdentity.GetCurrent())
            .IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);

    public bool Opened => _computer is not null;

    public void Open()
    {
        try
        {
            _computer = new Computer { IsCpuEnabled = true, IsGpuEnabled = true };
            _computer.Open();
            _cpu = _computer.Hardware.FirstOrDefault(h => h.HardwareType == HardwareType.Cpu);
            _gpu = PickGpu();
        }
        catch
        {
            _computer?.Close();
            _computer = null;
            _cpu = null;
            _gpu = null;
        }
    }

    // 多 GPU（核显 + 独显）优先带功率传感器、显存最大的那张
    private IHardware? PickGpu()
    {
        if (_computer is null) return null;
        var gpus = _computer.Hardware
            .Where(h => h.HardwareType is HardwareType.GpuNvidia or HardwareType.GpuAmd or HardwareType.GpuIntel)
            .ToList();
        if (gpus.Count == 0) return null;
        foreach (var gpu in gpus)
        {
            try { gpu.Update(); } catch { }
        }
        return gpus
            .OrderByDescending(h => PowerSensor(h) is not null)
            .ThenByDescending(h => VramMiB(h) ?? 0)
            .ThenByDescending(h => h.HardwareType == HardwareType.GpuNvidia)
            .ThenByDescending(h => h.HardwareType == HardwareType.GpuAmd)
            .First();
    }

    public (string? Name, double? Watts) ReadCpu()
    {
        if (_computer is null || _cpu is null) return (null, null);
        double? package = null;
        try
        {
            _cpu.Update();
            foreach (var sensor in _cpu.Sensors)
                if (sensor.SensorType == SensorType.Power && sensor.Name == "Package" && sensor.Value is { } value)
                    package = PowerReading.ValidateCpu(value);
        }
        catch { return (_cpu.Name, null); }
        return (_cpu.Name, package);
    }

    public GpuRead? ReadGpu()
    {
        if (_gpu is null) return null;
        try
        {
            _gpu.Update();
            var power = PowerSensor(_gpu)?.Value;
            var temp = TemperatureSensor(_gpu)?.Value;
            return new GpuRead(
                _gpu.Name,
                power is { } p ? PowerReading.ValidateGpu(p) : null,
                temp is { } t ? PowerReading.ValidateTemp(t) : null,
                VramMiB(_gpu));
        }
        catch { return null; }
    }

    // GPU Package 是整卡功耗；AMD 的 GPU PPT/Core/SoC 与 Intel 的 GPU Total 是分项/别名
    private static ISensor? PowerSensor(IHardware hw)
    {
        var sensors = hw.Sensors
            .Where(s => s.SensorType == SensorType.Power && s.Value is not null)
            .ToList();
        return sensors.FirstOrDefault(s => s.Name.Equals("GPU Package", StringComparison.OrdinalIgnoreCase))
            ?? sensors.FirstOrDefault(s => s.Name.Equals("GPU Power", StringComparison.OrdinalIgnoreCase))
            ?? sensors.FirstOrDefault(s => s.Name.Equals("GPU Total", StringComparison.OrdinalIgnoreCase))
            ?? sensors.FirstOrDefault(s => s.Name.Contains("Package", StringComparison.OrdinalIgnoreCase))
            ?? sensors.FirstOrDefault();
    }

    private static ISensor? TemperatureSensor(IHardware hw)
    {
        var sensors = hw.Sensors
            .Where(s => s.SensorType == SensorType.Temperature && s.Value is not null)
            .ToList();
        return sensors.FirstOrDefault(s => s.Name.Equals("GPU Core", StringComparison.OrdinalIgnoreCase))
            ?? sensors.FirstOrDefault(s => s.Name.Contains("Core", StringComparison.OrdinalIgnoreCase))
            ?? sensors.FirstOrDefault();
    }

    // LHM 的 Data 传感器单位是字节；AMD 不提供 Total，由 Used + Free 相加
    private static long? VramMiB(IHardware hw)
    {
        if (DataSensor(hw, "GPU Memory Total")?.Value is { } totalBytes && totalBytes > 0)
            return (long)Math.Round(totalBytes / 1048576.0);

        var used = DataSensor(hw, "GPU Memory Used")?.Value;
        var free = DataSensor(hw, "GPU Memory Free")?.Value;
        if (used is { } usedBytes && free is { } freeBytes && usedBytes > 0 && freeBytes > 0)
            return (long)Math.Round((usedBytes + freeBytes) / 1048576.0);

        return null;
    }

    private static ISensor? DataSensor(IHardware hw, string name) =>
        hw.Sensors.FirstOrDefault(s =>
            s.SensorType == SensorType.Data &&
            s.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

    public void Dispose()
    {
        _computer?.Close();
        _computer = null;
        _cpu = null;
        _gpu = null;
    }
}
