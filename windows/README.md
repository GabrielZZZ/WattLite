# WattLite for Windows

原生 Windows 10/11 实现（WPF）。与 macOS 版一样，只回答一个问题：这台机器此刻的主要部件吃进多少瓦。

> 当前版本 **0.1.1**，下载见 [Windows Release](https://github.com/GabrielZZZ/WattLite/releases/tag/v0.1.1-windows)。推荐使用安装版 `WattLite-0.1.1-windows-x64-setup.exe`；同一页面也提供免安装 zip。

## 功能

- **任务栏徽标**：托盘左侧常驻实时功率（CPU 封装 + GPU）。逐像素透明分层窗口，全屏应用盖住任务栏时自动隐藏；托盘图标始终保留，作为打开面板和退出的入口。
- **点击展开面板**：大数字 + 10 分钟趋势 + CPU / GPU / 内存 / 硬盘卡片（厂商 logo、型号、参数、各自读数）。
- **每块物理盘独立卡片**：显示盘符（如 `C:`、`D: E:`）与各自的实时写入速度。
- **明暗主题**：设置里手动切换深色/浅色，立即生效并持久化。
- **中英双语**：设置里即时切换。
- **纯本地**：无网络请求；历史按分钟聚合写入 `%APPDATA%\WattLite` 下的 CSV，可随时删除。

## 运行要求

- Windows 10 1809+ 或 Windows 11，x64
- 启动时需要管理员权限（`app.manifest` 为 `requireAdministrator`）：CPU 封装功率走 LibreHardwareMonitor/PawnIO，磁盘写入速度走 `IOCTL_DISK_PERFORMANCE`
- GPU 功率与温度来自 NVIDIA、AMD、Intel 驱动暴露的传感器；NVIDIA 的功耗上限与显存通过 `nvidia-smi`。虚拟机的虚拟显卡不提供功率传感器

主数字是 **CPU 封装功率 + GPU 功率**（带 `≈`），不含主板、内存、硬盘与电源转换损耗，不是插座端功率。

## 安装

- **安装版（推荐）**：`WattLite-0.1.1-windows-x64-setup.exe`。安装到 `C:\Program Files\WattLite`，创建开始菜单快捷方式和可选桌面快捷方式，写入「应用和功能」卸载项，支持中英安装界面。安装需要一次管理员权限。
- **免安装版**：`WattLite-0.1.1-windows-x64.zip`，解压后运行 `WattLite.exe`。
- 两者都自包含 .NET 运行时；主程序均需管理员权限。安装包与主程序目前未做代码签名。
- 卸载保留 `%APPDATA%\WattLite` 下的设置与历史。

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

生成安装包（需要 Inno Setup 6；默认探测当前用户或全局安装目录，也可传 `-Iscc`）：

```powershell
.\windows\installer\build-installer.ps1 -PublishDir .\publish -Version 0.1.1
```

产物在 `dist\`：`WattLite-0.1.1-windows-x64-setup.exe` 与 `.sha256`。安装器支持中英双语，安装到 Program Files，包含开始菜单/可选桌面快捷方式与卸载项。

## 目录

```
windows/
  WattLite/    WPF 主程序（任务栏徽标、面板、传感器、设置、主题）
  Checks/      控制台冒烟测试（nvidia-smi 行解析边界）
  installer/   Inno Setup 脚本、中英文安装界面资源、构建脚本
  README-portable.txt  免安装 zip 内的说明
  WattLite.sln
```

## 说明

- 厂商 logo 仅用于设备识别，商标归各厂商所有。
- MIT 许可，见仓库根目录 [LICENSE](../LICENSE)。

---

**English.** Native Windows 10/11 port built with WPF: a transparent taskbar badge with live CPU package + GPU power, a macOS-style panel, per-disk cards with drive letters and write speeds, light/dark themes, Chinese/English UI, and local-only CSV history. GPU sensors cover NVIDIA, AMD and Intel through LibreHardwareMonitor; NVIDIA's power limit and VRAM use `nvidia-smi`; virtual machines expose no virtual GPU power sensor. The release ships a standard Inno Setup installer (Program Files, Start Menu shortcut, uninstall entry) plus a portable zip; the app requires administrator rights. Build with `dotnet build windows/WattLite/WattLite.csproj -c Release`; create the installer with `windows\installer\build-installer.ps1`.
