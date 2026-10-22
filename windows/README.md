# WattLite for Windows

原生 Windows 10/11 实现（WPF）。与 macOS 版一样，只回答一个问题：这台机器此刻的主要部件吃进多少瓦。

> 首个版本 **0.1.0**，下载见 [Windows Release](https://github.com/GabrielZZZ/WattLite/releases/tag/v0.1.0-windows)。

## 功能

- **任务栏徽标**：托盘左侧常驻实时功率（CPU 封装 + NVIDIA GPU）。逐像素透明分层窗口，全屏应用盖住任务栏时自动隐藏。
- **点击展开面板**：大数字 + 10 分钟趋势 + CPU / GPU / 内存 / 硬盘卡片（厂商 logo、型号、参数、各自读数）。
- **每块物理盘独立卡片**：显示盘符（如 `C:`、`D: E:`）与各自的实时写入速度。
- **明暗主题**：设置里手动切换深色/浅色，立即生效并持久化。
- **中英双语**：设置里即时切换。
- **纯本地**：无网络请求；历史按分钟聚合写入 `%APPDATA%\WattLite` 下的 CSV，可随时删除。

## 运行要求

- Windows 10 1809+ 或 Windows 11，x64
- 启动时需要管理员权限（`app.manifest` 为 `requireAdministrator`）：CPU 封装功率走 LibreHardwareMonitor/PawnIO，磁盘写入速度走 `IOCTL_DISK_PERFORMANCE`
- 需要 NVIDIA 驱动及 `nvidia-smi` 才能读取 GPU 功率、温度、功耗上限和显存；没有独显时 CPU 侧仍可工作

主数字是 **CPU 封装功率 + GPU 功率**（带 `≈`），不含主板、内存、硬盘与电源转换损耗，不是插座端功率。

## 构建

```powershell
dotnet build windows/WattLite/WattLite.csproj -c Release
```

运行生成的 `WattLite.exe`，会弹 UAC。`Checks` 是 `nvidia-smi` 解析的命令行冒烟测试：

```powershell
dotnet run --project windows/Checks/Checks.csproj
```

自包含发布（无需目标机安装 .NET）：

```powershell
dotnet publish windows/WattLite/WattLite.csproj -c Release -r win-x64 `
  --self-contained true -p:PublishSingleFile=false -p:DebugType=None -o publish
```

## 目录

```
windows/
  WattLite/   WPF 主程序（任务栏徽标、面板、传感器、设置、主题）
  Checks/     控制台冒烟测试（nvidia-smi 行解析边界）
  WattLite.sln
```

## 说明

- 厂商 logo 仅用于设备识别，商标归各厂商所有。
- MIT 许可，见仓库根目录 [LICENSE](../LICENSE)。

---

**English.** Native Windows 10/11 port built with WPF: a transparent taskbar badge with live CPU package + NVIDIA GPU power, a macOS-style panel, per-disk cards with drive letters and write speeds, light/dark themes, Chinese/English UI, and local-only CSV history. Requires administrator rights; GPU data needs NVIDIA's `nvidia-smi`. Build with `dotnet build windows/WattLite/WattLite.csproj -c Release`.
