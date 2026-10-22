using System.Windows;

namespace WattLite;

public partial class App : System.Windows.Application
{
    private PowerStore? _store;
    private TrayIcon? _tray;
    private TaskbarBadge? _badge;
    private PanelWindow? _panel;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        Settings.Load();
        Theme.Apply(Settings.Current.Theme);
        _store = new PowerStore();
        _panel = new PanelWindow(_store);
        _badge = new TaskbarBadge
        {
            TogglePanel = () => _panel.Toggle(),
            OpenSettings = () => _panel.ShowSettings(),
        };
        if (_badge.Attached)
            _panel.AnchorProvider = _badge.Anchor;
        else
        {
            _tray = new TrayIcon(_store)
            {
                TogglePanel = _panel.Toggle,
                OpenSettings = () => _panel.ShowSettings(),
            };
        }
        _store.OnReading += reading =>
        {
            _badge.UpdateStatus(reading);
            _tray?.UpdateStatus(reading);
        };
        _badge.UpdateStatus(_store.Latest);
        _tray?.UpdateStatus(_store.Latest);
        _store.Start();
        if (e.Args.Contains("--show", StringComparer.OrdinalIgnoreCase))
            _panel.ShowPanel();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _badge?.Dispose();
        _tray?.Dispose();
        _store?.Dispose();
        base.OnExit(e);
    }
}
