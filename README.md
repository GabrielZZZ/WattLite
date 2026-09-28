# WattLite

<p align="left">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-green">
  <img alt="platform" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="arch" src="https://img.shields.io/badge/arch-arm64%20(Apple%20Silicon)-black">
  <img alt="deps" src="https://img.shields.io/badge/dependencies-0-brightgreen">
  <img alt="network" src="https://img.shields.io/badge/network-零请求-orange">
</p>

macOS 菜单栏功率监视器。只回答两个问题：**这台 Mac 此刻吃进多少瓦**，**电池此刻净充 / 净放多少瓦**。

菜单栏常驻（`LSUIElement`，无 Dock 图标），点开是功率面板。不控制充电、不发送任何网络请求、不采集序列号。

![实时面板](docs/screenshots/live.gif)

> 大数字、趋势曲线与粒子流都跟着系统当前功耗实时走。SMC 键 `PDTR` 是机器侧输入功率，插座端另有适配器转换损耗。

## 菜单栏

一个等宽数字，宽度固定，跳数时不左右挤动；bolt 图标带能量流动画（充电上行 / 放电下行 / 接电未充慢速环境流）。读的是系统缓存时会显式加 `≈` 标记，不冒充实时值。

![菜单栏](docs/screenshots/menubar.png)

## 面板

![功率面板](docs/screenshots/panel.png)

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

## 快速开始

```bash
git clone <this-repo> && cd WattLite
bash build.sh            # 先跑自检，再产出 build/WattLite.app
open build/WattLite.app
```

只需要 Xcode 命令行工具（`xcode-select --install`）。没有 Xcode 工程、没有 SwiftPM、没有第三方依赖。要求 Apple Silicon + macOS 14+。

自检是一个纯 `precondition` 的可执行程序，覆盖功率解码、边界与陈旧数据、会话能量积分、机型标识符查表：

```bash
build/checks             # PASS: ...
build/checks --live      # 再采 8 秒真实数据，对照 SMC 与 V×I
```

## 设置

![设置页](docs/screenshots/settings.png)

菜单栏显示指标（Mac 输入 / 电池净功率）、后台采样间隔（1 / 2 / 5 秒）、登录时启动。面板展开时固定每秒采样，睡眠时停止采集并在唤醒后重新采样。

## 机型与产品图自动联动

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

## 历史数据

按分钟聚合写本地 CSV：

```
~/Library/Application Support/WattLite/history/YYYY-MM-DD.csv
# ts,input_w,battery_w,percent,full_charge_mah,connected
```

CSV 本身就是导出格式，没有数据库、没有后台上传进程；删掉目录即清空。

## 已知限制

- **未签名**（ad-hoc 签名）。自己 `bash build.sh` 编译运行不受影响；从别处下载的 `.app` 会被 Gatekeeper 拦。
- **精度未经外部功率计校准**。`PDTR` 是机器侧输入功率，不是插座端功率。
- **只支持 Apple Silicon**：`build.sh` 的编译目标写死 `arm64-apple-macosx14.0`，要跑 Intel 得自己加通用二进制目标。
- 30 W / 240 W 档苹果适配器暂无公开原图；适配器 `Model` 十六进制 → A 编号的对照表目前只有 2 条经实测确认（`0x7016 → A2518`、`0x7002 → A2166`），没有权威公开来源，因此不猜。

## 许可

MIT，见 [LICENSE](LICENSE)。`Assets/Adapters/` 内的产品图为 Apple 官方素材，版权归 Apple Inc.。
