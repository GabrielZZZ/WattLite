using System.IO;
using System.Windows;

namespace WattLite;

public partial class App : System.Windows.Application
{
    private PowerStore? _store;
    private TrayIcon? _tray;
    private TaskbarBadge? _badge;
    private PanelWindow? _panel;

    private static void Log(string message)
    {
        try
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WattLite");
            Directory.CreateDirectory(dir);
            File.AppendAllText(Path.Combine(dir, "debug.log"),
                $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {message}{Environment.NewLine}");
        }
        catch
        {
            // Logging must never take the app down.
        }
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        Log($"START args=[{string.Join(' ', e.Args)}] admin={CpuReader.IsAdmin}");

        DispatcherUnhandledException += (_, args) =>
        {
            Log($"DISPATCHER {args.Exception}");
            MessageBox.Show(
                $"WattLite 出错：{args.Exception.Message}\n\n日志：%APPDATA%\\WattLite\\debug.log",
                "WattLite", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
            Shutdown(1);
        };
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            Log($"UNHANDLED {args.ExceptionObject}");

        try
        {
            Settings.Load();
            Theme.Apply(Settings.Current.Theme);
            _store = new PowerStore();
            _panel = new PanelWindow(_store);
            var badge = new TaskbarBadge
            {
                TogglePanel = () => _panel.Toggle(),
                OpenSettings = () => _panel.ShowSettings(),
            };
            _badge = badge;
            _panel.AnchorProvider = badge.Attached ? badge.Anchor : null;
            var tray = new TrayIcon(_store)
            {
                TogglePanel = _panel.Toggle,
                OpenSettings = () => _panel.ShowSettings(),
            };
            _tray = tray;
            _store.OnReading += reading =>
            {
                badge.UpdateStatus(reading);
                tray.UpdateStatus(reading);
            };
            badge.UpdateStatus(_store.Latest);
            tray.UpdateStatus(_store.Latest);
            Log($"WINDOW badge={badge.Attached} tray=true");
            _panel.ShowPanel(startup: true);
            _store.Start();
            Log("READY");
        }
        catch (Exception ex)
        {
            Log($"START FAILED {ex}");
            MessageBox.Show(
                $"WattLite 无法启动：{ex.Message}\n\n日志：%APPDATA%\\WattLite\\debug.log",
                "WattLite", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _badge?.Dispose();
        _tray?.Dispose();
        _store?.Dispose();
        base.OnExit(e);
    }
}
