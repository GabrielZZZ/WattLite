# WattLite

<p align="left">
  <a href="https://github.com/GabrielZZZ/WattLite/releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/GabrielZZZ/WattLite?color=blue"></a>
  <img alt="license" src="https://img.shields.io/badge/license-MIT-green">
  <img alt="platform" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="arch" src="https://img.shields.io/badge/arch-arm64%20(Apple%20Silicon)-black">
  <img alt="deps" src="https://img.shields.io/badge/dependencies-0-brightgreen">
  <img alt="network" src="https://img.shields.io/badge/network-none-orange">
</p>

**English** · [简体中文](#简体中文)

A macOS menu bar power monitor. It answers two questions and nothing else: **how many watts is this Mac pulling right now**, and **is the battery netting charge or discharge**.

It lives in the menu bar (`LSUIElement`, no Dock icon); click it for the power panel. It never controls charging, never makes a network request, and never reads your serial number.

![Live panel](docs/screenshots/live.gif)

> The big number, the trend line and the particle flow all track the machine's actual draw. The SMC key `PDTR` is input power measured *inside* the Mac — the wall outlet sees more, because the adapter itself burns some.

## Menu bar

One monospaced number with a fixed width, so it never shoves the rest of your menu bar sideways when it jumps. The bolt icon carries an energy-flow animation: upward while charging, downward on battery, a slow ambient drift when plugged in but not charging. When a value comes from the system cache rather than a live read it is prefixed with `≈` instead of pretending to be real time.

![Menu bar](docs/screenshots/menubar.png)

## Panel

![Power panel](docs/screenshots/panel.png)

| Block | Shows | Source |
| --- | --- | --- |
| Big number | Input power or battery net power | SMC key `PDTR`, read-only I/O Kit call (`Sources/SMC.c`) |
| Particle flow | Faster when the machine draws more | Local animation, no extra sampling |
| Trend | Last 10 minutes | 1 sample / second while the panel is open |
| Input voltage / current | Instantaneous V and A | Same SMC batch |
| Battery capacity | Current / full-charge mAh | `AppleSmartBattery` |
| Adapter card | Name, vendor, model, rated watts, product art | `AdapterDetails` + USB PD `FedDetails` |
| Mac card | Exact marketing name, CPU/GPU cores, memory | `system_profiler` + identifier lookup table |
| Session energy | Wh, duration, average since plugged in | Integrated from samples |

Battery net power = voltage × signed current: positive is charging, negative is discharging. The system refreshes it roughly once a minute, out of phase with the instantaneous input reading, so the panel deliberately **does not** subtract one from the other.

The panel also ships fully in English — switch it in Settings and it applies instantly, no restart:

![Power panel in English](docs/screenshots/panel-en.png)

Unplugged, the same panel switches to the battery view: the trend becomes discrete battery samples, the Mac card gains an estimated time remaining, and the session card counts energy given out instead of taken in.

![On battery, in English](docs/screenshots/panel-battery-en.png)

## Install

### Download (recommended)

Grab `WattLite-2.0.dmg` from [**Releases**](https://github.com/GabrielZZZ/WattLite/releases/latest) and drag WattLite into `Applications`.

The first launch needs one manual approval: this project has no Apple Developer account, so the build is ad-hoc signed and not notarised, and Gatekeeper blocks every copy that arrives through a browser. Either

- open **System Settings → Privacy & Security** and click **Open Anyway** next to "WattLite was blocked", or
- clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/WattLite.app
```

`WattLite-2.0.zip` works too, but **extract it by double-clicking or with `ditto -x -k`** — `unzip` leaves `._*` resource forks inside the bundle and breaks the signature seal.

After that the menu bar shows `⚡ 67W · in 9.0 W`. Click it for the panel, and turn on **Launch at login** in settings if you want it permanent.

### Build from source

```bash
git clone https://github.com/GabrielZZZ/WattLite.git && cd WattLite
bash build.sh                        # runs the self-checks, then emits build/WattLite.app
open build/WattLite.app
```

Xcode command line tools only (`xcode-select --install`). No Xcode project, no SwiftPM, no third-party dependencies. Requires Apple Silicon and macOS 14+.

```bash
bash build.sh release                # additionally emits build/WattLite-<version>.{dmg,zip}
```

The self-check is a plain `precondition` executable covering power decoding, edge cases and stale data, session energy integration, and the model identifier table:

```bash
build/checks             # PASS: ...
build/checks --live      # samples 8 more seconds and cross-checks SMC against V×I
```

## Settings

![Settings](docs/screenshots/settings.png)

![Settings in English](docs/screenshots/settings-en.png)

Interface language (简体中文 / English, applied instantly), which metric the menu bar shows (Mac input / battery net power), background sampling interval (1 / 2 / 5 seconds), and launch at login. While the panel is open it samples once per second regardless; sampling stops on sleep and restarts on wake.

## Model and artwork detection

`system_profiler` only returns a generic name ("MacBook Pro"). The exact marketing name comes from a 72-entry identifier table in `Sources/MacModels.swift`, sourced from Apple's official model identification pages. Artwork is keyed by identifier, because one marketing name can ship different hardware looks (M4 vs M4 Pro/Max).

Lookup is **user directory first, bundle second**, tried key by key:

```
~/Library/Application Support/WattLite/adapters/<key>.png   # yours
Contents/Resources/Adapters/<key>.png                        # shipped
```

- Mac: `mac16-8` (identifier) → `macbook-pro` (generic)
- Adapter: `apple-67w` (Apple bricks, by wattage) → `22D9:001B` (third party, by VID:PID)

Shipped: 72 official Mac product images + 9 Apple adapter images (20/29/35/61/67/70/87/96/140 W), all normalised to 600×600 transparent squares with the cable cropped out.

Third-party chargers usually report nothing but `pd charger` over USB PD, so there is nothing to auto-detect — the pencil button on the adapter card lets you set name / model / protocol and upload your own product image. Entries are saved to `adapters.json` and override the built-ins.

## History

Aggregated per minute into a local CSV:

```
~/Library/Application Support/WattLite/history/YYYY-MM-DD.csv
# ts,input_w,battery_w,percent,full_charge_mah,connected
```

The CSV *is* the export format — no database, no background uploader. Delete the folder to wipe everything.

## Known limitations

- **Ad-hoc signed, not notarised** (no Apple Developer account). Downloaded copies need the one-off approval above; a build you compiled yourself is unaffected.
- **Not calibrated against an external power meter.** `PDTR` is machine-side input power, not wall power.
- **Apple Silicon only**: `build.sh` hardcodes `arm64-apple-macosx14.0`. Add a universal target yourself for Intel.
- No official art available for the 30 W / 240 W Apple adapters. The adapter `Model` hex → A-number table has only two field-verified entries (`0x7016 → A2518`, `0x7002 → A2166`); there is no authoritative public source for the rest, so we do not guess.

## Release notes

**v2.0** — first packaged release, downloadable as `.dmg` / `.zip`.

- Mac model resolved to its exact marketing name (72-entry identifier table) and matched to official artwork by identifier
- 9 Apple adapter wattage classes shipped, normalised to transparent squares, brick only
- Third-party chargers can be described by hand (name / model / protocol + your own image); user entries override built-ins
- Session energy card added (Wh, duration, average)
- Panel reduced to one big number with power-driven particles; popover height pinned so it stops resizing between adapter and battery states
- Full English interface, switchable from Settings without restarting

## License

MIT, see [LICENSE](LICENSE). Product images under `Assets/Adapters/` are Apple's own assets and remain © Apple Inc.

---

## 简体中文

macOS 菜单栏功率监视器。只回答两个问题：**这台 Mac 此刻吃进多少瓦**，**电池此刻净充 / 净放多少瓦**。

菜单栏常驻（`LSUIElement`，无 Dock 图标），点开是功率面板。不控制充电、不发送任何网络请求、不采集序列号。[↑ English](#wattlite)

### 菜单栏

一个等宽数字，宽度固定，跳数时不左右挤动；bolt 图标带能量流动画（充电上行 / 放电下行 / 接电未充慢速环境流）。读的是系统缓存时会显式加 `≈` 标记，不冒充实时值。

### 面板

| 区块 | 内容 | 来源 |
| --- | --- | --- |
| 大数字 | 输入功率或电池净功率 | SMC `PDTR`，IOKit 只读调用（`Sources/SMC.c`） |
| 粒子流 | 功率越大流动越快 | 本地动画，无额外采样 |
| 趋势 | 近 10 分钟曲线 | 面板展开时每秒采样 |
| 输入电压 / 电流 | 瞬时 V、A | 同一批 SMC 读数 |
| 电池剩余容量 | 当前 / 满充 mAh | `AppleSmartBattery` |
| 适配器卡 | 名称、厂商、型号、额定功率、产品图 | `AdapterDetails` + USB PD `FedDetails` |
| 本机卡 | 精确营销名、CPU/GPU 核心、内存 | `system_profiler` + 标识符查表 |
| 本次接通输入能量 | Wh、时长、平均功率 | 采样积分 |

电池净功率 = 电压 × 有符号电流，正值充电、负值放电；系统约每分钟更新一次，与输入瞬时值不同步，所以面板**不做两者差值推算**。

![电池供电状态](docs/screenshots/panel-battery.png)

### 安装

从 [**Releases**](https://github.com/GabrielZZZ/WattLite/releases/latest) 下载 `WattLite-2.0.dmg`，打开后把 WattLite 拖进 `Applications`。

首次打开需要放行一次：项目没有 Apple Developer 账号，因此是 ad-hoc 签名、未经公证，Gatekeeper 会拦下所有从浏览器下载的副本。二选一：

- **系统设置 → 隐私与安全性**，在"已阻止使用 WattLite"处点 **仍要打开**；
- 终端去掉隔离标记：`xattr -dr com.apple.quarantine /Applications/WattLite.app`

也可以用 `WattLite-2.0.zip`，但**必须双击或用 `ditto -x -k` 解压**——`unzip` 会把资源派生数据解成一堆 `._` 文件留在包里，签名封条当场失效。

装好后菜单栏出现 `⚡ 67W · 入 9.0 W`，点它展开面板。设置里可打开**登录时启动**。

### 从源码构建

```bash
git clone https://github.com/GabrielZZZ/WattLite.git && cd WattLite
bash build.sh                        # 先跑自检，再产出 build/WattLite.app
open build/WattLite.app
```

只需要 Xcode 命令行工具（`xcode-select --install`）。没有 Xcode 工程、没有 SwiftPM、没有第三方依赖。要求 Apple Silicon + macOS 14+。`bash build.sh release` 额外产出 `build/WattLite-<版本>.{dmg,zip}`。

自检是一个纯 `precondition` 的可执行程序，覆盖功率解码、边界与陈旧数据、会话能量积分、机型标识符查表：

```bash
build/checks             # PASS: ...
build/checks --live      # 再采 8 秒真实数据，对照 SMC 与 V×I
```

### 设置

界面语言（简体中文 / English，切换立即生效）、菜单栏显示指标（Mac 输入 / 电池净功率）、后台采样间隔（1 / 2 / 5 秒）、登录时启动。面板展开时固定每秒采样，睡眠时停止采集并在唤醒后重新采样。

### 机型与产品图自动联动

`system_profiler` 只给泛称（"MacBook Pro"），精确营销名由 `Sources/MacModels.swift` 的标识符查表得到（72 项，来源为 Apple 官方机型识别页）。产品图按标识符配图，因为同一营销名会有不同外观（M4 与 M4 Pro/Max 的机器图不同）。

查找顺序是**用户目录优先，bundle 兜底**，逐个键尝试：

```
~/Library/Application Support/WattLite/adapters/<key>.png   # 你放的
Contents/Resources/Adapters/<key>.png                       # 内置的
```

- 本机：`mac16-8`（标识符）→ `macbook-pro`（泛称）
- 适配器：`apple-67w`（苹果头按功率档）→ `22D9:001B`（第三方按 VID:PID）

内置 72 张 Mac 官方产品图 + 9 档苹果适配器图（20/29/35/61/67/70/87/96/140 W），适配器统一为 600×600 透明方图、只保留机身。

第三方充电头在 USB PD 里通常只报 `pd charger`，无法自动识别品牌型号，因此适配器卡上的铅笔按钮支持自行填写名称 / 型号 / 协议并上传产品图，存进 `adapters.json`，用户条目覆盖内置条目。

### 历史数据

按分钟聚合写本地 CSV：`~/Library/Application Support/WattLite/history/YYYY-MM-DD.csv`（`ts,input_w,battery_w,percent,full_charge_mah,connected`）。CSV 本身就是导出格式，没有数据库、没有后台上传进程；删掉目录即清空。

### 已知限制

- **未签名**（ad-hoc 签名，无 Apple Developer 账号，因此也无法公证）。从浏览器下载的 `.dmg` / `.zip` 首次打开会被 Gatekeeper 拦，见上文「安装」；自己 `bash build.sh` 编译出的副本不受影响。
- **精度未经外部功率计校准**。`PDTR` 是机器侧输入功率，不是插座端功率。
- **只支持 Apple Silicon**：`build.sh` 的编译目标写死 `arm64-apple-macosx14.0`，要跑 Intel 得自己加通用二进制目标。
- 30 W / 240 W 档苹果适配器暂无公开原图；适配器 `Model` 十六进制 → A 编号的对照表目前只有 2 条经实测确认（`0x7016 → A2518`、`0x7002 → A2166`），没有权威公开来源，因此不猜。

### 更新记录

**v2.0** — 第一个正式发行版，提供 `.dmg` / `.zip` 直接下载安装。

- 本机型号自动识别到精确营销名（72 项标识符查表），并按标识符自动配官方产品图
- 苹果适配器内置 9 档功率图，统一 600×600 透明方图、只保留机身
- 第三方充电头可自建档案：名称 / 型号 / 协议 + 上传产品图，用户条目覆盖内置条目
- 新增本次接通输入能量卡（Wh、时长、平均功率）
- 面板统一为单个大数字 + 功率驱动的粒子流；popover 高度固定，不再在接电 / 电池两态间抖动
- 界面完整支持英文，设置里可切换，无需重启

### 许可

MIT，见 [LICENSE](LICENSE)。`Assets/Adapters/` 内的产品图为 Apple 官方素材，版权归 Apple Inc.
