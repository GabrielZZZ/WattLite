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

    private readonly CpuReader _cpu = new();
    private readonly PowerLog _log = new();
    private DispatcherTimer? _timer;
    private readonly SemaphoreSlim _busy = new(1);
    private bool _sleeping;
    private int _generation;

    public void Start()
    {
        NvidiaSmi.Discover();
        if (CpuReader.IsAdmin)
            _cpu.Open();
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
            var gpu = NvidiaSmi.ExecutablePath is null ? null : await NvidiaSmi.ReadAsync().ConfigureAwait(true);
            var cpu = await Task.Run(_cpu.Read).ConfigureAwait(true);
            if (_sleeping || ticket != _generation) return;

            string? issue = null;
            if (NvidiaSmi.ExecutablePath is null)
                issue = "未找到 nvidia-smi，GPU 数据不可用";
            else if (gpu is null)
                issue = "GPU 数据不可用";
            if (!CpuReader.IsAdmin)
                issue ??= null; // GPU 优先；CPU 问题仅在 GPU 正常时展示

            var reading = new PowerReading
            {
                CapturedAt = DateTime.Now,
                CpuWatts = CpuReader.IsAdmin ? cpu.Watts : null,
                GpuWatts = gpu?.DrawWatts,
                GpuLimitWatts = gpu?.LimitWatts,
                TemperatureC = gpu?.TempC,
                CpuName = cpu.Name,
                GpuName = gpu?.Name,
                VramMiB = gpu?.VramMiB,
                Issue = issue ?? (CpuReader.IsAdmin && cpu.Watts is null ? "CPU 功率不可用" : null),
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

    public void Dispose()
    {
        Stop();
        _cpu.Dispose();
    }
}
