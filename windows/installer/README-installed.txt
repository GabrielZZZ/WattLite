WattLite 0.1.0 for Windows
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
- GPU power, temperature, power limit and VRAM require an NVIDIA GPU with a
  current driver and nvidia-smi on PATH or in the driver directory.
- Click the gear button in the panel for appearance, language and sampling
  settings. Changes apply immediately.
- The taskbar badge hides automatically when a fullscreen app covers the
  taskbar.

Uninstalling
------------
Use Settings > Apps > Installed apps (or Apps & Features) and select WattLite.
The uninstaller removes the program and its shortcuts. Your settings and
history are kept.

Local data
----------
%APPDATA%\WattLite\
  settings.json   appearance, language and sampling interval
  history\        one CSV per day, aggregated per minute
  debug.log       minimal local diagnostics

WattLite makes no network requests. Delete the folder above to reset the app
or clear the history.

Links
-----
Website:  https://gabrielzzz.github.io/WattLite/
Source:   https://github.com/GabrielZZZ/WattLite
Releases: https://github.com/GabrielZZZ/WattLite/releases
License:  MIT (see LICENSE.txt)

--

WattLite 0.1.0 Windows 版
=========================

WattLite 是原生功率监视器：任务栏徽标和托盘图标显示 CPU + GPU 实时功率，
点击徽标或托盘图标可展开完整面板。

使用说明
--------
- 启动需要管理员权限。Windows 只向提权进程开放 CPU 封装功率、PawnIO 传感器
  驱动和逐盘性能计数器，因此启动时请在 UAC 弹窗点「是」。
- 启动后会直接打开面板。关闭面板后程序继续在任务栏/托盘运行，点击任务栏
  徽标或托盘图标可再次打开。
- GPU 功率、温度、功耗上限与显存需要 NVIDIA 显卡及较新的驱动，并确保
  nvidia-smi 在 PATH 或驱动目录中。
- 面板右下角的齿轮按钮可设置外观、界面语言和采样间隔，修改立即生效。
- 全屏应用覆盖任务栏时，任务栏徽标会自动隐藏。

卸载
----
在「设置 → 应用 → 已安装的应用」（或「应用和功能」）中选择 WattLite 卸载。
卸载会移除程序与快捷方式，但保留你的设置和历史。

本地数据
--------
%APPDATA%\WattLite\
  settings.json   外观、语言、采样间隔
  history\        按天保存的分钟级 CSV
  debug.log       少量本地诊断日志

WattLite 不发起任何网络请求。删除上述目录即可重置应用或清空历史。

链接
----
官网：  https://gabrielzzz.github.io/WattLite/
源码：  https://github.com/GabrielZZZ/WattLite
发布页：https://github.com/GabrielZZZ/WattLite/releases
许可：  MIT（见 LICENSE.txt）
