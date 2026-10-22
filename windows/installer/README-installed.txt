WattLite 1.0.0 for Windows
==========================

WattLite is a native power monitor. It lives next to the notification area:
the taskbar badge and tray icon show live CPU + GPU power, and clicking either
opens the full panel.

Getting started
---------------
- WattLite needs administrator rights. Windows only exposes CPU package power,
  the PawnIO sensor driver and per-disk performance counters to elevated
  processes, so accept the UAC prompt when starting the app.
- The panel opens on launch. Close it and WattLite keeps running in the
  taskbar/tray; click the taskbar badge or tray icon to open it again.
- GPU power and temperature come from NVIDIA, AMD and Intel GPUs when the
  driver exposes sensors. NVIDIA also reads power limit and VRAM through
  nvidia-smi. Virtual machines' virtual GPUs expose no power sensors.
- Click the gear button in the panel for appearance, language, sampling and
  update settings. Changes apply immediately.
- The taskbar badge hides automatically when a fullscreen app covers the
  taskbar.
- Automatic updates are on by default: WattLite checks 20 seconds after
  launch and every six hours. It downloads a signed installer, verifies its
  SHA-256, installs silently, and restarts. Turn this off in Settings, or use
  Check for updates there.
- The portable build does not replace itself; it points you to the download
  page when a new version is available.

Uninstalling
------------
Use Settings > Apps > Installed apps (or Apps & Features) and select WattLite.
The uninstaller removes the program and its shortcuts. Your settings and
history are kept.

Local data
----------
%APPDATA%\WattLite\
  settings.json   appearance, language, sampling and update settings
  history\        one CSV per day, aggregated per minute
  debug.log       minimal local diagnostics

%LOCALAPPDATA%\WattLite\
  updates\        downloaded installers awaiting installation

WattLite's only network traffic is checking for updates and downloading them.
It sends no telemetry or personal data, and update checks can be disabled in
Settings. Delete the `%APPDATA%` folder to reset the app or clear its history;
the `%LOCALAPPDATA%` folder only holds cached installers.

Links
-----
Website:  https://gabrielzzz.github.io/WattLite/
Source:   https://github.com/GabrielZZZ/WattLite
Releases: https://github.com/GabrielZZZ/WattLite/releases
License:  MIT (see LICENSE.txt)

--

WattLite 1.0.0 Windows 版
=========================

WattLite 是原生功率监视器：任务栏徽标和托盘图标显示 CPU + GPU 实时功率，
点击徽标或托盘图标可展开完整面板。

使用说明
--------
- 启动需要管理员权限。Windows 只向提权进程开放 CPU 封装功率、PawnIO 传感器
  驱动和逐盘性能计数器，因此启动时请在 UAC 弹窗点「是」。
- 启动后会直接打开面板。关闭面板后程序继续在任务栏/托盘运行，点击任务栏
  徽标或托盘图标可再次打开。
- GPU 功率与温度来自 NVIDIA、AMD、Intel 显卡（需要驱动暴露对应传感器）；
  NVIDIA 还会通过 nvidia-smi 读取功耗上限与显存。虚拟机的虚拟显卡不提供
  功率传感器。
- 面板右下角的齿轮按钮可设置外观、界面语言、采样间隔和更新，修改立即生效。
- 全屏应用覆盖任务栏时，任务栏徽标会自动隐藏。
- 自动更新默认开启：启动 20 秒后检查，之后每 6 小时检查一次。发现新版本后
  下载签名安装包，校验 SHA-256，静默安装并自动重启。可在设置里关闭自动检查，
  也可手动点「检查更新」。
- 免安装版不会自动替换自身；发现新版本时会引导到下载页。

卸载
----
在「设置 → 应用 → 已安装的应用」（或「应用和功能」）中选择 WattLite 卸载。
卸载会移除程序与快捷方式，但保留你的设置和历史。

本地数据
--------
%APPDATA%\WattLite\
  settings.json   外观、语言、采样与更新设置
  history\        按天保存的分钟级 CSV
  debug.log       少量本地诊断日志

%LOCALAPPDATA%\WattLite\
  updates\        已下载、等待安装的安装包

WattLite 的联网行为只有检查和下载更新，不发送遥测或个人数据；自动检查可在
设置里关闭。删除 `%APPDATA%` 目录即可重置应用或清空历史；`%LOCALAPPDATA%`
目录只存放已下载的安装包。

链接
----
官网：  https://gabrielzzz.github.io/WattLite/
源码：  https://github.com/GabrielZZZ/WattLite
发布页：https://github.com/GabrielZZZ/WattLite/releases
许可：  MIT（见 LICENSE.txt）
