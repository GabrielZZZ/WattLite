using System.IO;
using System.Windows.Threading;
using Microsoft.Win32;

namespace WattLite;

public sealed class PowerStore : IDisposable
{
    public PowerReading Latest { get; private set; } = PowerReading.Unavailable(Strings.T("正在读取"));
    public List<(DateTime At, double Watts)> History { get; } = new();
    public SessionEnergy Session { get; } = new();
    public MachineInfo? Machine { get; private set; }

    public event Action<PowerReading>? OnReading;

    public double Interval
    {
        get => Settings.Current.Interval;
        set
        {
            Settings.Current.Interval = value;
            Settings.Save();
            Schedule();
        }
    }

    public bool Visible { get; set; }

    private readonly HardwareReader _hardware = new();
    private readonly PowerLog _log = new();
    private DispatcherTimer? _timer;
    private readonly SemaphoreSlim _busy = new(1);
    private Task _hardwareReady = Task.CompletedTask;
    private bool _sleeping;
    private int _generation;

    public void Start()
    {
        NvidiaSmi.Discover();
        // LHM 的 GPU 传感器需要 MTA；WPF 启动线程是 STA，放到线程池初始化
        _hardwareReady = Task.Run(_hardware.Open);
        SystemEvents.PowerModeChanged += OnPowerMode;
        Task.Run(() => Machine = MachineInfo.Detect());
        Schedule();
        _ = SampleAsync();
    }

    public void SetVisible(bool value)
    {
        Visible = value;
        if (value) _ = SampleAsync();
        Schedule();
    }

    private void Schedule()
    {
        _timer?.Stop();
        if (_sleeping) return;
        var seconds = Visible ? 1 : Interval;
        _timer ??= new DispatcherTimer();
        _timer.Tick -= OnTimerTick;
        _timer.Tick += OnTimerTick;
        _timer.Interval = TimeSpan.FromSeconds(seconds);
        _timer.Start();
    }

    private void OnTimerTick(object? sender, EventArgs e) => _ = SampleAsync();

    private async Task SampleAsync()
    {
        if (_sleeping) return;
        if (!await _busy.WaitAsync(0)) return;
        var ticket = _generation;
        try
        {
            await _hardwareReady.ConfigureAwait(true);
            var nvidia = NvidiaSmi.ExecutablePath is null ? null : await NvidiaSmi.ReadAsync().ConfigureAwait(true);
            var (cpu, lhmGpu) = await Task.Run(() => (_hardware.ReadCpu(), _hardware.ReadGpu())).ConfigureAwait(true);
            if (_sleeping || ticket != _generation) return;

            var gpu = MergeGpu(nvidia, lhmGpu);
            string? issue = null;
            if (gpu is null)
                issue = MachineInfo.IsVirtualGpu(Machine?.GpuName)
                    ? "虚拟机未暴露 GPU 功率传感器"
                    : "未检测到可用的 GPU 功率传感器";
            else if (gpu.Value.Watts is null)
                issue = "GPU 功率传感器不可用";
            if (HardwareReader.IsAdmin && cpu.Watts is null && issue is null)
                issue = "CPU 功率不可用";

            var reading = new PowerReading
            {
                CapturedAt = DateTime.Now,
                CpuWatts = HardwareReader.IsAdmin ? cpu.Watts : null,
                GpuWatts = gpu?.Watts,
                GpuLimitWatts = gpu?.Limit,
                TemperatureC = gpu?.Temp,
                CpuName = cpu.Name,
                GpuName = gpu?.Name,
                VramMiB = gpu?.Vram,
                Issue = issue,
            };

            if (reading.TotalWatts is { } total)
            {
                History.Add((reading.CapturedAt, total));
                History.RemoveAll(p => (reading.CapturedAt - p.At).TotalSeconds > 600);
                while (History.Count > 1300) History.RemoveAt(0);
                Session.Add(total, reading.CapturedAt);
            }

            Latest = reading;
            OnReading?.Invoke(reading);
            _log.Record(reading);
        }
        catch { }
        finally
        {
            _busy.Release();
        }
    }

    private void OnPowerMode(object? sender, PowerModeChangedEventArgs e)
    {
        switch (e.Mode)
        {
            case PowerModes.Suspend:
                _sleeping = true;
                _generation++;
                _timer?.Stop();
                _log.Flush();
                break;
            case PowerModes.Resume:
                _sleeping = false;
                _generation++;
                Session.Reset();
                History.Clear();
                Latest = PowerReading.Unavailable(Strings.T("唤醒后重新采样"));
                OnReading?.Invoke(Latest);
                Schedule();
                _ = SampleAsync();
                break;
        }
    }

    public void Stop()
    {
        _sleeping = true;
        _generation++;
        _timer?.Stop();
        _log.Flush();
        SystemEvents.PowerModeChanged -= OnPowerMode;
    }

    private readonly record struct GpuReading(
        string? Name, double? Watts, double? Limit, double? Temp, long? Vram);

    // nvidia-smi 提供 NVIDIA 的功耗上限/显存；其余字段和 AMD/Intel 由 LHM 补足
    private static GpuReading? MergeGpu(NvidiaSmi.GpuSample? nvidia, HardwareReader.GpuRead? lhm)
    {
        if (nvidia is null && lhm is null) return null;
        return new GpuReading(
            nvidia?.Name ?? lhm?.Name,
            nvidia?.DrawWatts ?? lhm?.Watts,
            nvidia?.LimitWatts,
            nvidia?.TempC ?? lhm?.TempC,
            nvidia?.VramMiB ?? lhm?.VramMiB);
    }

    public void Dispose()
    {
        Stop();
        _hardware.Dispose();
    }
}
