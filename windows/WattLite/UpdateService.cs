using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows.Threading;
using Microsoft.Win32;

namespace WattLite;

public enum UpdatePhase
{
    Idle,
    Checking,
    UpToDate,
    Downloading,
    Ready,
    Failed,
    Portable,
    Applying
}

public sealed record UpdateState(
    UpdatePhase Phase,
    string? Version = null,
    double Progress = 0,
    string? Error = null);

// 清单用离线私钥签名，App 只带公钥；SHA-256 之外再验一层，避免更新源被替换。
public sealed class UpdateService : IDisposable
{
    private const string PrimaryManifest = "https://gabrielzzz.github.io/WattLite/updates/windows.json";
    private const string FallbackManifest = "https://cdn.jsdelivr.net/gh/GabrielZZZ/WattLite@main/docs/updates/windows.json";
    private const string PublicKeyBase64 = "BJv6XS95bB96D4D7KX2g0T8sDgmqb6CkIjoTmL5iVSC2OAv0S/LE2tsPPKJxqHximpc959zfAXO0Fj+NzjePyAM=";
    private const string DownloadPage = "https://gabrielzzz.github.io/WattLite/#download";
    private const string UninstallKey =
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{BACB135C-5D62-4516-9629-C1B167CB3760}_is1";

    private static readonly TimeSpan CheckInterval = TimeSpan.FromHours(6);
    private static readonly TimeSpan StartupDelay = TimeSpan.FromSeconds(20);

    public event Action? StateChanged;
    public UpdateState State { get; private set; } = new(UpdatePhase.Idle);

    public static Version CurrentVersion =>
        typeof(UpdateService).Assembly.GetName().Version ?? new Version(1, 0, 0);
    public static string CurrentVersionText => CurrentVersion.ToString(3);

    private readonly HttpClient _http;
    private readonly DispatcherTimer _timer;
    private readonly string _updatesDir;
    private CancellationTokenSource? _cts;
    private UpdateInfo? _pending;
    private string? _installerPath;
    private bool _started;
    private bool _busy;

    public UpdateService()
    {
        var handler = new SocketsHttpHandler
        {
            ConnectTimeout = TimeSpan.FromSeconds(15),
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate
        };
        _http = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        _http.DefaultRequestHeaders.UserAgent.ParseAdd($"WattLite/{CurrentVersionText} (Windows)");
        _http.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue { NoCache = true };

        _updatesDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WattLite", "updates");
        _timer = new DispatcherTimer { Interval = CheckInterval };
        _timer.Tick += (_, _) => _ = CheckAsync(manual: false);
    }

    public void Start()
    {
        if (_started) return;
        _started = true;
        CleanupOldDownloads();
        if (Settings.Current.AutoUpdate)
        {
            _timer.Start();
            _ = DelayedStartAsync();
        }
    }

    private async Task DelayedStartAsync()
    {
        try { await Task.Delay(StartupDelay); }
        catch { return; }
        if (Settings.Current.AutoUpdate) await CheckAsync(manual: false);
    }

    public void SetAutoUpdate(bool enabled)
    {
        Settings.Current.AutoUpdate = enabled;
        Settings.Save();
        if (!enabled)
        {
            _cts?.Cancel();
            _timer.Stop();
            SetState(new UpdateState(UpdatePhase.Idle));
            return;
        }

        if (!_started) return;
        _timer.Start();
        _ = CheckAsync(manual: false);
    }

    public async Task CheckAsync(bool manual)
    {
        if (!_started) _started = true;
        if (_busy) return;

        _busy = true;
        var cts = new CancellationTokenSource();
        _cts = cts;
        try
        {
            SetState(new UpdateState(UpdatePhase.Checking));
            Log($"UPDATE check manual={manual}");

            var payload = await FetchManifestAsync(cts.Token);
            if (payload is null)
            {
                SetState(new UpdateState(UpdatePhase.Failed, Error: "check"));
                return;
            }

            var info = ParseManifest(payload.Value.Json, AllowHttp);
            if (info is null)
            {
                Log("UPDATE manifest rejected");
                SetState(new UpdateState(UpdatePhase.Failed, Error: "check"));
                return;
            }

            if (info.ParsedVersion.CompareTo(CurrentVersion) <= 0)
            {
                Log($"UPDATE up-to-date local={CurrentVersionText} remote={info.Version}");
                SetState(new UpdateState(UpdatePhase.UpToDate, CurrentVersionText));
                return;
            }

            _pending = info;
            Log($"UPDATE available {info.Version}");
            if (!IsInstalled())
            {
                Log("UPDATE available for portable build");
                SetState(new UpdateState(UpdatePhase.Portable, info.Version));
                return;
            }
            await DownloadAsync(info, cts.Token);
        }
        catch (OperationCanceledException)
        {
            Log("UPDATE canceled");
            if (!Settings.Current.AutoUpdate) SetState(new UpdateState(UpdatePhase.Idle));
        }
        catch (Exception ex)
        {
            Log($"UPDATE failed {ex}");
            SetState(new UpdateState(UpdatePhase.Failed, Error: "check"));
        }
        finally
        {
            _busy = false;
            if (ReferenceEquals(_cts, cts)) _cts = null;
            cts.Dispose();
        }
    }

    public bool Apply()
    {
        if (State.Phase != UpdatePhase.Ready || _installerPath is null || _pending is null) return false;
        if (!IsInstalled())
        {
            Log("UPDATE apply skipped: portable build");
            SetState(new UpdateState(UpdatePhase.Portable, _pending.Version));
            return false;
        }

        try
        {
            // The cache lives under LocalAppData, so re-check the bytes immediately before
            // handing them to an elevated installer instead of trusting the earlier download.
            if (!File.Exists(_installerPath) ||
                !string.Equals(HashFile(_installerPath), _pending.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                Log("UPDATE apply rejected: installer hash mismatch");
                TryDelete(_installerPath);
                _installerPath = null;
                SetState(new UpdateState(UpdatePhase.Failed, _pending.Version, Error: "verify"));
                return false;
            }

            // The app already runs elevated, so Setup inherits the admin token and no extra UAC appears.
            // /UPDATE=1 makes the installer restart WattLite after replacing the files.
            var psi = new ProcessStartInfo
            {
                FileName = _installerPath,
                Arguments = "/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /UPDATE=1",
                UseShellExecute = false,
                WorkingDirectory = Path.GetDirectoryName(_installerPath)!
            };
            SetState(new UpdateState(UpdatePhase.Applying, _pending.Version));
            Process.Start(psi);
            Log($"UPDATE apply version={_pending.Version} installer={_installerPath}");
            System.Windows.Application.Current.Shutdown();
            return true;
        }
        catch (Exception ex)
        {
            Log($"UPDATE apply failed {ex}");
            SetState(new UpdateState(UpdatePhase.Failed, _pending.Version, Error: "apply"));
            return false;
        }
    }

    public void OpenDownloadPage()
    {
        try
        {
            Process.Start(new ProcessStartInfo(DownloadPage) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Log($"UPDATE open page failed {ex.Message}");
        }
    }

    private async Task<ManifestPayload?> FetchManifestAsync(CancellationToken ct)
    {
        foreach (var url in ManifestUrls())
        {
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeout.CancelAfter(TimeSpan.FromSeconds(20));
                var json = await _http.GetByteArrayAsync(url, timeout.Token);
                var signature = Encoding.UTF8.GetString(
                    await _http.GetByteArrayAsync(url + ".sig", timeout.Token)).Trim();
                if (!VerifySignature(json, signature, PublicKeyBase64))
                {
                    Log($"UPDATE signature invalid {url}");
                    continue;
                }
                return new ManifestPayload(json, url);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException)
            {
                Log($"UPDATE manifest timeout {url}");
            }
            catch (Exception ex)
            {
                Log($"UPDATE manifest {url} {ex.Message}");
            }
        }
        return null;
    }

    private async Task DownloadAsync(UpdateInfo info, CancellationToken ct)
    {
        try
        {
            Directory.CreateDirectory(_updatesDir);
            var final = Path.Combine(_updatesDir, $"WattLite-{info.Version}-windows-x64-setup.exe");
            if (File.Exists(final) && await HashMatchesAsync(final, info.Sha256, ct))
            {
                _installerPath = final;
                SetState(new UpdateState(UpdatePhase.Ready, info.Version));
                Log($"UPDATE ready from cache {info.Version}");
                return;
            }

            var part = final + ".part";
            foreach (var url in new[] { info.Url, info.Mirror }
                         .Where(u => !string.IsNullOrWhiteSpace(u))
                         .Select(u => u!)
                         .Distinct(StringComparer.OrdinalIgnoreCase))
            {
                try
                {
                    SetState(new UpdateState(UpdatePhase.Downloading, info.Version, 0));
                    await DownloadOneAsync(url, part, info.Version, ct);
                    if (!await HashMatchesAsync(part, info.Sha256, ct))
                        throw new InvalidDataException("SHA-256 mismatch");
                    File.Move(part, final, true);
                    _installerPath = final;
                    SetState(new UpdateState(UpdatePhase.Ready, info.Version));
                    Log($"UPDATE ready {info.Version} {url}");
                    return;
                }
                catch (OperationCanceledException) when (!ct.IsCancellationRequested)
                {
                    Log($"UPDATE download timeout {url}");
                    TryDelete(part);
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    Log($"UPDATE download {url} {ex.Message}");
                    TryDelete(part);
                }
            }

            SetState(new UpdateState(UpdatePhase.Failed, info.Version, Error: "download"));
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            Log($"UPDATE download failed {ex}");
            SetState(new UpdateState(UpdatePhase.Failed, info.Version, Error: "download"));
        }
    }

    private async Task DownloadOneAsync(string url, string path, string version, CancellationToken ct)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromMinutes(20));

        using var response = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength ?? 0;

        await using var input = await response.Content.ReadAsStreamAsync(timeout.Token);
        await using var output = new FileStream(
            path, FileMode.Create, FileAccess.Write, FileShare.None, 81920, useAsync: true);

        var buffer = new byte[81920];
        long done = 0;
        long lastReport = 0;
        while (true)
        {
            var read = await input.ReadAsync(buffer.AsMemory(), timeout.Token);
            if (read == 0) break;
            await output.WriteAsync(buffer.AsMemory(0, read), timeout.Token);
            done += read;
            if (total > 0 && (done - lastReport >= 512 * 1024 || done == total))
            {
                lastReport = done;
                SetState(new UpdateState(UpdatePhase.Downloading, version,
                    Math.Min(1, (double)done / total)));
            }
        }

        if (total > 0 && done != total)
            throw new IOException($"incomplete download {done}/{total}");
    }

    private static async Task<bool> HashMatchesAsync(string path, string expected, CancellationToken ct)
    {
        var actual = await Task.Run(() => HashFile(path), ct);
        return string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase);
    }

    private static string HashFile(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    internal static bool VerifySignature(byte[] payload, string signatureBase64, string publicKeyBase64)
    {
        try
        {
            var raw = Convert.FromBase64String(publicKeyBase64.Trim());
            if (raw.Length != 65 || raw[0] != 0x04) return false;
            using var key = ECDsa.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint
                {
                    X = raw.AsSpan(1, 32).ToArray(),
                    Y = raw.AsSpan(33, 32).ToArray()
                }
            });
            var signature = Convert.FromBase64String(signatureBase64.Trim());
            return key.VerifyData(payload, signature, HashAlgorithmName.SHA256,
                DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        }
        catch
        {
            return false;
        }
    }

    internal static UpdateInfo? ParseManifest(byte[] json, bool allowHttp)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (!root.TryGetProperty("version", out var versionElement) ||
                !Version.TryParse(versionElement.GetString(), out var version))
                return null;

            var url = ReadUrl(root, "url", allowHttp);
            if (url is null) return null;
            var mirror = ReadUrl(root, "mirror", allowHttp);
            var sha = root.TryGetProperty("sha256", out var shaElement)
                ? shaElement.GetString()?.Trim().ToLowerInvariant()
                : null;
            if (sha is null || sha.Length != 64 || !sha.All(Uri.IsHexDigit)) return null;

            return new UpdateInfo(versionElement.GetString()!, version, url, mirror, sha);
        }
        catch
        {
            return null;
        }
    }

    private static string? ReadUrl(JsonElement root, string name, bool allowHttp)
    {
        if (!root.TryGetProperty(name, out var element)) return null;
        var text = element.GetString();
        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri)) return null;
        if (uri.Scheme == Uri.UriSchemeHttps) return uri.ToString();
        return allowHttp && uri.Scheme == Uri.UriSchemeHttp ? uri.ToString() : null;
    }

    private static IEnumerable<string> ManifestUrls()
    {
        var overrideUrl = Environment.GetEnvironmentVariable("WATTLITE_UPDATE_MANIFEST");
        if (!string.IsNullOrWhiteSpace(overrideUrl))
        {
            yield return overrideUrl.Trim();
            yield break;
        }
        yield return PrimaryManifest;
        yield return FallbackManifest;
    }

    private static bool AllowHttp =>
        !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("WATTLITE_UPDATE_MANIFEST"));

    private bool IsInstalled()
    {
        var exe = Environment.ProcessPath;
        if (exe is null) return false;
        var full = Path.GetFullPath(exe);
        var exeDir = Path.GetDirectoryName(full);
        if (exeDir is not null && File.Exists(Path.Combine(exeDir, "unins000.exe")))
            return true;

        foreach (var root in new[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser })
        {
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                try
                {
                    using var baseKey = RegistryKey.OpenBaseKey(root, view);
                    using var key = baseKey.OpenSubKey(UninstallKey);
                    if (key?.GetValue("InstallLocation") is not string location || location.Length == 0)
                        continue;
                    var dir = Path.GetFullPath(location.Trim().Trim('"').TrimEnd('\\'));
                    if (full.StartsWith(dir + "\\", StringComparison.OrdinalIgnoreCase))
                        return true;
                }
                catch
                {
                    // A missing/denied uninstall key just means "not the installed build".
                }
            }
        }

        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var fallback = Path.Combine(programFiles, "WattLite");
        return full.StartsWith(fallback + "\\", StringComparison.OrdinalIgnoreCase);
    }

    private void CleanupOldDownloads()
    {
        try
        {
            if (!Directory.Exists(_updatesDir)) return;
            foreach (var file in Directory.GetFiles(_updatesDir))
            {
                var isPartial = file.EndsWith(".part", StringComparison.OrdinalIgnoreCase);
                var old = File.GetLastWriteTimeUtc(file) < DateTime.UtcNow.AddDays(-7);
                if (isPartial || old) TryDelete(file);
            }
        }
        catch
        {
            // Cache cleanup is best-effort.
        }
    }

    private void SetState(UpdateState state)
    {
        State = state;
        StateChanged?.Invoke();
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

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
            // Logging must never break updating.
        }
    }

    public void Dispose()
    {
        try { _cts?.Cancel(); } catch { }
        _timer.Stop();
        _http.Dispose();
    }

    private readonly record struct ManifestPayload(byte[] Json, string Url);
    internal sealed record UpdateInfo(
        string Version, Version ParsedVersion, string Url, string? Mirror, string Sha256);
}
