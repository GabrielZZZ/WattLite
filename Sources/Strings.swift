import Combine
import Foundation

enum AppLang: String, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }
    /// 语言名自称，不随界面语言变
    var title: String { self == .zh ? "简体中文" : "English" }
}

// ponytail: 中文原文就是键。数据模型继续产出中文，只有渲染处查表，
// 所以设置里切换语言立即生效；表里没有的串回落原文，永远不会渲染成空白。
final class L10n: ObservableObject {
    static let shared = L10n()
    @Published var lang: AppLang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "lang") }
    }

    private init() {
        lang = AppLang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "")
            ?? (Locale.current.language.languageCode?.identifier == "zh" ? .zh : .en)
    }
}

func T(_ zh: String) -> String {
    L10n.shared.lang == .en ? (Strings.en[zh] ?? zh) : zh
}

/// 带插值的串：中文格式做键，英文格式用同一组占位符、同一顺序
func TF(_ zh: String, _ args: CVarArg...) -> String {
    String(format: L10n.shared.lang == .en ? (Strings.en[zh] ?? zh) : zh, arguments: args)
}

enum Strings {
    static let en: [String: String] = [
        // 电源状态
        "数据不可用": "Data unavailable",
        "电池供电": "On battery",
        "已接电 · 电池辅助供电": "Plugged in · Battery assisting",
        "正在充电": "Charging",
        "已接电 · 未充电": "Plugged in · Not charging",
        "已接电 · 状态未知": "Plugged in · Status unknown",
        "正在读取": "Reading…",
        "唤醒后重新采样": "Resampling after wake",
        // 指标与标签
        "Mac 输入": "Mac input",
        "电池净功率": "Battery net",
        "入": "In",
        "电池": "Batt",
        "待机放电": "Idle discharge",
        "电池净放电": "Battery net discharge",
        "电池净充电": "Battery net charge",
        "输入功率趋势": "Input power trend",
        "电池采样点": "Battery samples",
        "等待有效采样": "Waiting for samples",
        "实时读取": "Live",
        "系统采样": "System sample",
        // 采样来源与异常
        "电源状态不可用": "Power state unavailable",
        "电池采样过期或不可用": "Battery sample stale or unavailable",
        "输入为系统缓存，并非实时采样": "Input is a system cache, not a live reading",
        "未找到内置电池": "No internal battery found",
        "无法读取电源遥测": "Cannot read power telemetry",
        "系统缓存采样，非实时值": "System-cached sample, not live",
        "SMC 输入侧实时读取": "Live SMC input reading",
        "SMC 直读 · 输入侧功率": "Live SMC · input side",
        "系统缓存 · 非实时输入": "System cache · not live input",
        "系统采样时间未知": "System sample time unknown",
        "输入电压": "Input voltage",
        "输入电流": "Input current",
        "电池剩余容量": "Battery remaining",
        // 时间
        "%d 小时 %d 分": "%dh %dm",
        "%d 分": "%d min",
        "不足 1 分": "Under 1 min",
        "预计剩余": "Est. remaining",
        "10 分钟前": "10 min ago",
        "系统采样 · %d 秒前": "System sample · %d s ago",
        "最近十分钟，%d 个有效采样，范围 %d 至 %d 瓦":
            "Last ten minutes, %d valid samples, range %d to %d watts",
        "%d W · 现在": "%d W · now",
        // 本机与适配器
        "这台 Mac": "This Mac",
        "%d 核 CPU（%d 性能 + %d 能效）": "%d-core CPU (%dP + %dE)",
        "%d 核 GPU": "%d-core GPU",
        "%@ 统一内存": "%@ unified memory",
        "本机 %@，%@，%@": "This Mac %@, %@, %@",
        "未知适配器": "Unknown adapter",
        "型号": "Model",
        "额定 %.1f V · %.2f A": "Rated %.1f V · %.2f A",
        "产品图": "Product picture",
        "无产品图": "No picture",
        "暂无充电头产品图": "No adapter picture yet",
        "暂无本机图": "No Mac picture yet",
        "点击卡片右侧铅笔按钮可上传产品图，或手动放到 ~/Library/Application Support/WattLite/adapters/":
            "Use the pencil button on the right of the card to upload a product picture, "
            + "or drop one into ~/Library/Application Support/WattLite/adapters/",
        // 会话能量
        "本次接通输入能量": "Input energy this session",
        "本次断接放出能量": "Energy discharged this session",
        "时长": "Duration",
        "平均功率": "Average",
        "本次会话能量 %@ 瓦时": "Session energy %@ Wh",
        // 面板
        "电量 %d%%": "Battery %d%%",
        "本地运行 · 无网络请求": "Runs locally · No network requests",
        "返回功率面板": "Back to power panel",
        "设置": "Settings",
        "退出 WattLite": "Quit WattLite",
        "功率数据说明": "About these readings",
        "Mac 输入：优先读取 SMC PDTR，包含机器运行与充电所需电能，不是插座端功率。\n\n电池净功率：电池电压 × 有符号电流。正值充电，负值放电；系统通常约每分钟更新，不能与输入瞬时值直接相减。\n\n适配器容量是供电能力，不是实时功率。传感器为未公开接口，精度未经外部功率计校准；不可用时不估造数据。":
            "Mac input: SMC PDTR where available — the power this machine draws to run and charge, "
            + "not what the wall outlet supplies.\n\n"
            + "Battery net: battery voltage × signed current. Positive is charging, negative is discharging. "
            + "The system usually refreshes it about once a minute, so it cannot be subtracted from an instant input reading.\n\n"
            + "Adapter wattage is a supply capability, not live power. These sensors are undocumented interfaces and are "
            + "not calibrated against an external power meter; when data is unavailable it is left blank rather than estimated.",
        "%@ %@ 瓦": "%@ %@ watts",
        "充电头 %@，%@": "Charger %@, %@",
        "电池净功率正值为充电、负值为放电；与输入采样不同步，不作差值推算。":
            "Battery net: positive charging, negative discharging; not synced with input.",
        "编辑适配器图案与信息": "Edit adapter artwork and info",
        // 设置
        "保持轻巧。\n只看重要的功率。": "Stay light.\nOnly the power that matters.",
        "菜单栏显示": "Menu bar metric",
        "电池净功率为系统缓存，菜单栏用 ≈ 标记。":
            "Battery net power is system-cached, so the menu bar marks it with ≈.",
        "后台采样间隔": "Background sampling",
        "1 秒": "1 s",
        "2 秒": "2 s",
        "5 秒": "5 s",
        "面板展开时每秒读取；睡眠时停止采集。":
            "The panel reads once per second while open; sampling stops during sleep.",
        "界面语言": "Interface language",
        "切换后立即生效，无需重启。": "Applies instantly, no restart needed.",
        "登录时启动": "Launch at login",
        "打开登录项设置": "Open Login Items settings",
        "请在系统设置的登录项中允许 WattLite。": "Allow WattLite in System Settings › Login Items.",
        "无法更改登录启动：%@": "Could not change login start: %@",
        "只读电源数据，不控制充电；历史按分钟聚合存本地 CSV，可随时删除。":
            "Reads power data only and never controls charging. History is aggregated per minute into local CSV "
            + "and can be deleted at any time.",
        // 适配器编辑
        "适配器资料": "Adapter profile",
        "选择图片…": "Choose image…",
        "撤销新图": "Undo new image",
        "保存时转为 PNG，存到本地 adapters 目录": "Converted to PNG and saved into the local adapters folder",
        "名称": "Name",
        "快充协议": "Fast-charge protocols",
        "如 OPPO SUPERVOOC 100W 小方瓶 Pro": "e.g. OPPO SUPERVOOC 100W",
        "外壳印的型号，如 OSA00CB9BC": "Model printed on the shell, e.g. OSA00CB9BC",
        "如 SUPERVOOC · PD · PPS · QC3.0": "e.g. SUPERVOOC · PD · PPS · QC3.0",
        "保存": "Save",
        "删除自定义": "Delete custom",
        "识别键 %@": "Identity key %@",
        "资料仅保存在本机 ~/Library/Application Support/WattLite/":
            "Stored only on this Mac under ~/Library/Application Support/WattLite/",
        "当前适配器没有可用的识别信息（无 USB ID 与名称），无法保存自定义资料。请插上适配器后再试。":
            "This adapter reports no identity (no USB ID, no name), so a custom profile cannot be saved. "
            + "Plug the adapter in and try again.",
        // 菜单栏
        "WattLite 功率监测": "WattLite power monitor",
        "入 ≈88.8 W": "In ≈88.8 W",
        "电池 ≈-88.8 W": "Batt ≈-88.8 W",
    ]
}
