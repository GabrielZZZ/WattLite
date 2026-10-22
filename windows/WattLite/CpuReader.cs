using LibreHardwareMonitor.Hardware;

namespace WattLite;

public sealed class CpuReader : IDisposable
{
    private Computer? _computer;
    private IHardware? _cpu;

    public static bool IsAdmin =>
        new System.Security.Principal.WindowsPrincipal(System.Security.Principal.WindowsIdentity.GetCurrent())
            .IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);

    public bool Opened => _computer != null && _cpu != null;

    public void Open()
    {
        try
        {
            _computer = new Computer { IsCpuEnabled = true };
            _computer.Open();
            _cpu = _computer.Hardware.FirstOrDefault(h => h.HardwareType == HardwareType.Cpu);
        }
        catch
        {
            _computer?.Close();
            _computer = null;
            _cpu = null;
        }
    }

    public (string? Name, double? Watts) Read()
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

    public void Dispose()
    {
        _computer?.Close();
        _computer = null;
        _cpu = null;
    }
}
