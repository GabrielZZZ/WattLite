WattLite 0.1.0 for Windows (x64)
================================

Portable build: keep every file in this folder together, then run WattLite.exe.
A regular installer is also available on the releases page.

WattLite is a native power monitor. The taskbar badge and tray icon show live
CPU + GPU power; click either to open the full panel.

Getting started
---------------
- Accept the UAC prompt. Windows only exposes CPU package power, the PawnIO
  sensor driver and per-disk performance counters to elevated processes.
- The panel opens on launch. Close it and WattLite stays in the taskbar/tray;
  click the taskbar badge or tray icon to open it again.
- If SmartScreen says "Windows protected your PC", choose More info > Run anyway.
  This build is not code-signed.
- GPU power, temperature, power limit and VRAM require an NVIDIA GPU with a
  current driver and nvidia-smi available on PATH or in the driver directory.
- The taskbar badge hides automatically when a fullscreen app covers the
  taskbar. Right-click the tray icon for Settings or Exit.

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
License:  MIT (see LICENSE)

--

WattLite 0.1.0 Windows 版（x64）
================================

免安装版：请保持本目录所有文件在一起，双击 WattLite.exe 运行。
发布页同时提供常规安装包。

WattLite 是原生功率监视器：任务栏徽标和托盘图标显示 CPU + GPU 实时功率，
点击徽标或托盘图标可展开完整面板。

使用说明
--------
- 请在 UAC 弹窗点「是」。Windows 只向提权进程开放 CPU 封装功率、PawnIO
  传感器驱动和逐盘性能计数器。
- 启动后会直接打开面板。关闭面板后程序继续在任务栏/托盘运行，点击任务栏
  徽标或托盘图标可再次打开。
- 若 SmartScreen 提示「Windows 已保护你的电脑」：更多信息 → 仍要运行。
  本构建未做代码签名。
- GPU 功率、温度、功耗上限与显存需要 NVIDIA 显卡及较新的驱动，并确保
  nvidia-smi 在 PATH 或驱动目录中。
- 全屏应用覆盖任务栏时，任务栏徽标会自动隐藏。右键托盘图标可设置或退出。

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
许可：  MIT（见 LICENSE）
