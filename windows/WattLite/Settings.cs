using System.IO;
using System.Text.Json;

namespace WattLite;

public sealed class Settings
{
    public string Lang { get; set; } = "zh";
    public string Theme { get; set; } = "dark";
    public double Interval { get; set; } = 2;
    public bool AutoUpdate { get; set; } = true;

    public static Settings Current { get; private set; } = new();

    private static string DirectoryPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WattLite");
    private static string FilePath => Path.Combine(DirectoryPath, "settings.json");

    public static void Load()
    {
        try
        {
            if (File.Exists(FilePath))
                Current = JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new();
        }
        catch { Current = new(); }
        if (Current.Interval is not (1 or 2 or 5)) Current.Interval = 2;
        if (Current.Lang is not ("zh" or "en")) Current.Lang = "zh";
        if (Current.Theme is not ("dark" or "light")) Current.Theme = "dark";
    }

    public static void Save()
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(Current, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }
}
