using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace WattLite;

// 面板右侧的两项实时指标：内存已用（GlobalMemoryStatusEx）与整机磁盘写入速率
// （IOCTL_DISK_PERFORMANCE 的累计写入字节差分；应用本身以管理员运行）
public static class SystemMetrics
{
    public static ulong? UsedPhysicalMemoryBytes()
    {
        var status = new MEMORYSTATUSEX { Length = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
        return GlobalMemoryStatusEx(ref status) ? status.TotalPhys - status.AvailPhys : null;
    }

    private static readonly Dictionary<int, long> LastWrittenBytes = new();
    private static readonly Dictionary<int, long> LastSampleTicks = new();

    public static IReadOnlyDictionary<int, double?> DiskWriteSpeeds(IEnumerable<int> diskIndices)
    {
        var speeds = new Dictionary<int, double?>();
        var now = Stopwatch.GetTimestamp();
        foreach (var index in diskIndices.Distinct())
        {
            if (!TryReadWrittenBytes(index, out var total))
            {
                speeds[index] = null;
                continue;
            }
            if (LastWrittenBytes.TryGetValue(index, out var previous) && LastSampleTicks.TryGetValue(index, out var ticks))
            {
                var elapsed = (now - ticks) / (double)Stopwatch.Frequency;
                var delta = total - previous;
                speeds[index] = elapsed < 0.2 || delta < 0 ? null : delta / elapsed;
            }
            else speeds[index] = null;
            LastWrittenBytes[index] = total;
            LastSampleTicks[index] = now;
        }
        return speeds;
    }

    public static string SpeedText(double? bytesPerSecond) => bytesPerSecond is not { } speed
        ? "—"
        : speed >= 1L << 30 ? $"{speed / (1L << 30):0.0} GB/s"
        : speed >= 1L << 20 ? $"{speed / (1L << 20):0.0} MB/s"
        : speed >= 1L << 10 ? $"{speed / (1L << 10):0.0} KB/s"
        : $"{speed:0} B/s";

    private static bool TryReadWrittenBytes(int index, out long bytes)
    {
        bytes = 0;
        using var handle = CreateFile($@"\\.\PhysicalDrive{index}",
            GenericRead, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (handle.IsInvalid) return false;
        var buffer = new byte[128];
        if (!DeviceIoControl(handle, IoctlDiskPerformance, IntPtr.Zero, 0, buffer, (uint)buffer.Length, out var returned, IntPtr.Zero)
            || returned < 16)
            return false;
        // DISK_PERFORMANCE: BytesRead (8 bytes) 之后是 BytesWritten
        bytes = BitConverter.ToInt64(buffer, 8);
        return true;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORYSTATUSEX
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhys;
        public ulong AvailPhys;
        public ulong TotalPageFile;
        public ulong AvailPageFile;
        public ulong TotalVirtual;
        public ulong AvailVirtual;
        public ulong AvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX status);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share,
        IntPtr security, uint create, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(SafeFileHandle handle, uint code, IntPtr inBuffer, uint inSize,
        byte[] outBuffer, uint outSize, out uint returned, IntPtr overlapped);

    private const uint GenericRead = 0x8000_0000;
    private const uint FileShareRead = 0x1, FileShareWrite = 0x2;
    private const uint OpenExisting = 3;
    private const uint IoctlDiskPerformance = 0x0007_0020;
}
