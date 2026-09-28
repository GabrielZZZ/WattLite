# WattLite

macOS 菜单栏功率监视器。只显示两件事：Mac 此刻吃进多少瓦，电池此刻净充/净放多少瓦。

菜单栏常驻（`LSUIElement`，无 Dock 图标），点开是功率面板：大数字 + 趋势图 + 电压电流 + 电池剩余容量 + 适配器卡 + 本机卡 + 本次会话能量。

## 构建

```bash
bash build.sh          # 先跑自检，再产出 build/WattLite.app
open build/WattLite.app
```

只需要 Xcode 命令行工具（`xcode-select --install`），没有 Xcode 工程、没有 SwiftPM、没有第三方依赖。要求 macOS 14+ / Apple Silicon。

自检是一个纯 `precondition` 的可执行程序（`Tests/Checks.swift`），覆盖功率解码、边界与陈旧数据、会话能量积分、机型标识符查表：

```bash
build/checks          # PASS: ...
build/checks --live   # 再采 8 秒真实数据，对照 SMC 与 V×I
```

## 数据来源

- **Mac 输入功率**：SMC 键 `PDTR`（`Sources/SMC.c`，IOKit 只读调用）。读不到时明确标注"系统缓存 · 非实时输入"，不估造数据。
- **电池净功率**：`AppleSmartBattery` 的电压 × 有符号电流。正值充电、负值放电；系统约每分钟更新一次，与输入瞬时值不同步，因此面板不做两者差值推算。
- **本机型号**：`system_profiler` 只给泛称（"MacBook Pro"），精确营销名由 `Sources/MacModels.swift` 的标识符查表得到（72 项，来源为 Apple 官方机型识别页）。查不到时显示 `泛称 (标识符)`。
- **适配器**：`AdapterDetails` + USB PD `FedDetails`（厂商/产品 ID、额定电压电流）。

只读这几种数据，不发送任何网络请求，不采集序列号/UUID。

## 图片与自定义

产品图按两级键查找，先查用户目录再查 bundle：

```
~/Library/Application Support/WattLite/adapters/<key>.png
```

- 本机：`mac16-8`（标识符）→ `macbook-pro`（泛称）
- 适配器：`apple-67w`（苹果头按功率档）或 `22D9:001B`（第三方按 VID:PID）

苹果适配器内置 20/29/35/61/67/70/87/96/140 W 官方图，统一为 600×600 透明方图、只保留机身（在售档取商店原图，停产档取支持站示意图抠白底并按最大实心连通块裁掉线缆）。第三方充电头在 USB PD 里通常只报"pd charger"，无法自动识别品牌型号，因此面板里的铅笔按钮支持自行填写名称/型号/协议并上传产品图，保存在 `adapters.json`，用户条目覆盖内置条目。

## 历史

按分钟聚合写 `~/Library/Application Support/WattLite/history/<日期>.csv`（`ts,input_w,battery_w,percent,full_charge_mah,connected`）。CSV 本身即导出格式，删目录即清空。

## 已知限制

- 未签名（ad-hoc 签名），从别处下载的 `.app` 会被 Gatekeeper 拦；自己 `bash build.sh` 编译运行不受影响。
- 精度未经外部功率计校准，PDTR 是机器侧输入功率，不是插座端功率。
- 只支持 Apple Silicon：`build.sh` 的编译目标写死 `arm64-apple-macosx14.0`。要跑 Intel 得自己加通用二进制目标。

## 许可

MIT，见 [LICENSE](LICENSE)。`Assets/Adapters/` 内的产品图为 Apple 官方素材，版权归 Apple Inc.。
