using WattLite;

var failures = 0;
void Check(string name, bool ok)
{
    Console.WriteLine($"{(ok ? "PASS" : "FAIL")}  {name}");
    if (!ok) failures++;
}

// ---- nvidia-smi 行解析边界 ----
var normal = NvidiaSmi.ParseLine("NVIDIA GeForce RTX 5080, 44.09, 360.00, 31");
Check("解析正常行", normal is not null && normal.Name == "NVIDIA GeForce RTX 5080"
    && normal.DrawWatts == 44.09 && normal.LimitWatts == 360.00 && normal.TempC == 31);

var notAvailable = NvidiaSmi.ParseLine("NVIDIA GeForce RTX 5080, N/A, 360.00, N/A");
Check("N/A 字段置空", notAvailable is not null && notAvailable.DrawWatts is null && notAvailable.TempC is null
    && notAvailable.LimitWatts == 360.00);

var bracketed = NvidiaSmi.ParseLine("RTX 5080, [N/A], [N/A], [N/A]");
Check("[N/A] 字段置空", bracketed is not null && bracketed.DrawWatts is null && bracketed.LimitWatts is null
    && bracketed.TempC is null);

Check("空行返回 null", NvidiaSmi.ParseLine("") is null && NvidiaSmi.ParseLine(null) is null);
Check("字段不足返回 null", NvidiaSmi.ParseLine("RTX 5080, 44") is null);

var multiGpu = NvidiaSmi.ParseOutput("NVIDIA GeForce RTX 5080, 44.09, 360.00, 31\nNVIDIA GeForce RTX 3060, 12.5, 170.00, 40\n");
Check("多 GPU 取第一行", multiGpu is not null && multiGpu.Name == "NVIDIA GeForce RTX 5080" && multiGpu.DrawWatts == 44.09);

var leadingBlank = NvidiaSmi.ParseOutput("\n\nNVIDIA GeForce RTX 5080, 44.09, 360.00, 31\n");
Check("跳过前导空行", leadingBlank is not null && leadingBlank.DrawWatts == 44.09);
Check("全空输出返回 null", NvidiaSmi.ParseOutput("") is null && NvidiaSmi.ParseOutput("\n \n") is null);

// ---- 数值边界校验 ----
Check("CPU 0/300 边界合法", PowerReading.ValidateCpu(0) == 0 && PowerReading.ValidateCpu(300) == 300);
Check("CPU 负值/超范围丢弃", PowerReading.ValidateCpu(-1) is null && PowerReading.ValidateCpu(300.1) is null);
Check("GPU 0/600 边界合法", PowerReading.ValidateGpu(0) == 0 && PowerReading.ValidateGpu(600) == 600);
Check("GPU 负值/超范围丢弃", PowerReading.ValidateGpu(-0.1) is null && PowerReading.ValidateGpu(600.5) is null);
Check("温度边界与越界", PowerReading.ValidateTemp(110) == 110 && PowerReading.ValidateTemp(111) is null
    && PowerReading.ValidateTemp(-1) is null);

var badRange = NvidiaSmi.ParseLine("RTX 5080, 9999, 360.00, 31");
Check("超范围 GPU 值丢弃", badRange is not null && badRange.DrawWatts is null);

// ---- 主数字退化 ----
var both = new PowerReading { CpuWatts = 52.18, GpuWatts = 44.09 };
Check("双部件求和", Math.Abs(both.TotalWatts!.Value - 96.27) < 1e-9 && both.HasBothParts);
var cpuOnly = new PowerReading { CpuWatts = 52.18 };
Check("GPU 缺失退化为 CPU", cpuOnly.TotalWatts == 52.18 && cpuOnly.HasBothParts == false);
var gpuOnly = new PowerReading { GpuWatts = 44.09 };
Check("CPU 缺失时主数字 = GPU", gpuOnly.TotalWatts == 44.09 && gpuOnly.HasBothParts == false);
Check("双缺失主数字为空", new PowerReading().TotalWatts is null);
Check("脏值格式化为 —", PowerReading.PowerText(null) == "—" && PowerReading.PowerText(double.NaN) == "—");

// ---- 会话能量积分 ----
var session = new SessionEnergy();
var start = new DateTime(2026, 10, 21, 12, 0, 0);
session.Add(60, start);
session.Add(60, start.AddSeconds(1));
Check("1 秒 60 W 积分 = 60/3600 Wh", Math.Abs(session.Wh - 60.0 / 3600) < 1e-12 && Math.Abs(session.Seconds - 1) < 1e-9);
Check("平均功率", Math.Abs(session.AverageWatts!.Value - 60) < 1e-9);

session.Add(60, start.AddSeconds(2 + 31)); // 缺口 31 s，不计入
Check("缺口 > 30 s 不计入", Math.Abs(session.Seconds - 1) < 1e-9);
session.Add(60, start.AddSeconds(2 + 31 + 29)); // 距上次 29 s，计入
Check("缺口 < 30 s 计入", Math.Abs(session.Seconds - 30) < 1e-9);

session.Reset();
Check("会话清零", session.Wh == 0 && session.Seconds == 0 && session.AverageWatts is null);

// CPU 缺失时积分继续（用 GPU 值）
var degraded = new SessionEnergy();
degraded.Add(44, start);
degraded.Add(44, start.AddSeconds(1));
Check("退化值积分继续", Math.Abs(degraded.Wh - 44.0 / 3600) < 1e-12);

// ---- 参照物分档选取 ----
Check("低于最小档无换算", SessionEnergy.Comparison(0.05) is null);
var banana = SessionEnergy.Comparison(0.122);
Check("0.122 Wh = 1 根香蕉", banana is not null && banana.Value.Zh.Contains("香蕉") && Math.Abs(banana.Value.Count - 1) < 1e-9);
var battery = SessionEnergy.Comparison(3.0);
Check("3 Wh = 1 节电池", battery is not null && battery.Value.Zh.Contains("电池") && Math.Abs(battery.Value.Count - 1) < 1e-9);
var justBelow = SessionEnergy.Comparison(2.99);
Check("2.99 Wh 仍为香蕉档", justBelow is not null && justBelow.Value.Zh.Contains("香蕉"));
var dryer = SessionEnergy.Comparison(250.0);
Check("250 Wh = 1 次吹风机", dryer is not null && dryer.Value.Zh.Contains("吹风机") && Math.Abs(dryer.Value.Count - 1) < 1e-9);
var kettle = SessionEnergy.Comparison(249.9);
Check("249.9 Wh 仍为烧水档", kettle is not null && kettle.Value.Zh.Contains("烧开") && kettle.Value.Zh.Contains("🫖"));
var kwh = SessionEnergy.Comparison(2999.99);
Check("2999.99 Wh = 度电档", kwh is not null && kwh.Value.Zh.Contains("度电"));
var ev = SessionEnergy.Comparison(3000.0);
Check("3000 Wh = 20 公里电动车（unitWh=150）", ev is not null && ev.Value.Zh.Contains("电动车") && Math.Abs(ev.Value.Count - 20) < 1e-9);
Check("计数恒 ≥ 1", SessionEnergy.Comparison(0.122)!.Value.Count >= 1 && SessionEnergy.Comparison(3.0)!.Value.Count >= 1);

// ---- CSV 行格式与解析 ----
var row = PowerLog.FormatRow(1761024000, 52.18, 44.09, 31);
Check("CSV 行格式", row == "1761024000,52.18,44.09,31.00");
var parsed = PowerLog.ParseRow(row);
Check("CSV 行解析往返", parsed is not null
    && ((DateTimeOffset)parsed.Value.Ts).ToUnixTimeSeconds() == 1761024000
    && Math.Abs(parsed.Value.Cpu!.Value - 52.18) < 1e-9 && Math.Abs(parsed.Value.Gpu!.Value - 44.09) < 1e-9
    && Math.Abs(parsed.Value.Temp!.Value - 31) < 1e-9);

var sparse = PowerLog.FormatRow(1761024060, null, 44.09, null);
Check("缺失列留空", sparse == "1761024060,,44.09,");
var parsedSparse = PowerLog.ParseRow(sparse);
Check("缺失列解析为 null", parsedSparse is not null && parsedSparse.Value.Cpu is null
    && Math.Abs(parsedSparse.Value.Gpu!.Value - 44.09) < 1e-9 && parsedSparse.Value.Temp is null);

Check("CSV 头部", PowerLog.Header == "ts,cpu_w,gpu_w,temperature");
Check("CSV 非法行返回 null", PowerLog.ParseRow("not,a,row") is null && PowerLog.ParseRow(null) is null);

Console.WriteLine(failures == 0 ? "\nALL CHECKS PASSED" : $"\n{failures} CHECK(S) FAILED");
return failures == 0 ? 0 : 1;
