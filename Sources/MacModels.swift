import Foundation

/// 机型标识符 → Apple 官方营销名（与「关于本机」一致）。
/// 数据取自 support.apple.com 的 Identify your Mac… 系列页面（108052 / 102869 / 108054 / 102852 / 102231）。
/// 只收 macOS 14 能跑的机型（2018 年及以后）；查不到时调用方回落到 system_profiler 的泛称。
enum MacModels {
    static let names: [String: String] = [
        // MacBook Air
        "MacBookAir8,1": "MacBook Air (Retina, 13-inch, 2018)",
        "MacBookAir8,2": "MacBook Air (Retina, 13-inch, 2019)",
        "MacBookAir9,1": "MacBook Air (Retina, 13-inch, 2020)",
        "MacBookAir10,1": "MacBook Air (M1, 2020)",
        "Mac14,2": "MacBook Air (M2, 2022)",
        "Mac14,15": "MacBook Air (15-inch, M2, 2023)",
        "Mac15,12": "MacBook Air (13-inch, M3, 2024)",
        "Mac15,13": "MacBook Air (15-inch, M3, 2024)",
        "Mac16,12": "MacBook Air (13-inch, M4, 2025)",
        "Mac16,13": "MacBook Air (15-inch, M4, 2025)",
        "Mac17,3": "MacBook Air (13-inch, M5, 2026)",
        "Mac17,4": "MacBook Air (15-inch, M5, 2026)",
        // MacBook Pro
        "MacBookPro15,1": "MacBook Pro (15-inch, 2018–2019)",
        "MacBookPro15,2": "MacBook Pro (13-inch, 2018–2019, Four Thunderbolt 3 Ports)",
        "MacBookPro15,3": "MacBook Pro (15-inch, 2019)",
        "MacBookPro15,4": "MacBook Pro (13-inch, 2019, Two Thunderbolt 3 Ports)",
        "MacBookPro16,1": "MacBook Pro (16-inch, 2019)",
        "MacBookPro16,2": "MacBook Pro (13-inch, 2020, Four Thunderbolt 3 Ports)",
        "MacBookPro16,3": "MacBook Pro (13-inch, 2020, Two Thunderbolt 3 Ports)",
        "MacBookPro16,4": "MacBook Pro (16-inch, 2019)",
        "MacBookPro17,1": "MacBook Pro (13-inch, M1, 2020)",
        "MacBookPro18,1": "MacBook Pro (16-inch, 2021)",
        "MacBookPro18,2": "MacBook Pro (16-inch, 2021)",
        "MacBookPro18,3": "MacBook Pro (14-inch, 2021)",
        "MacBookPro18,4": "MacBook Pro (14-inch, 2021)",
        "Mac14,5": "MacBook Pro (14-inch, 2023)",
        "Mac14,6": "MacBook Pro (16-inch, 2023)",
        "Mac14,7": "MacBook Pro (13-inch, M2, 2022)",
        "Mac14,9": "MacBook Pro (14-inch, 2023)",
        "Mac14,10": "MacBook Pro (16-inch, 2023)",
        "Mac15,3": "MacBook Pro (14-inch, Nov 2023)",
        "Mac15,6": "MacBook Pro (14-inch, Nov 2023)",
        "Mac15,7": "MacBook Pro (16-inch, Nov 2023)",
        "Mac15,8": "MacBook Pro (14-inch, Nov 2023)",
        "Mac15,9": "MacBook Pro (16-inch, Nov 2023)",
        "Mac15,10": "MacBook Pro (14-inch, Nov 2023)",
        "Mac15,11": "MacBook Pro (16-inch, Nov 2023)",
        "Mac16,1": "MacBook Pro (14-inch, 2024)",
        "Mac16,5": "MacBook Pro (16-inch, 2024)",
        "Mac16,6": "MacBook Pro (14-inch, 2024)",
        "Mac16,7": "MacBook Pro (16-inch, 2024)",
        "Mac16,8": "MacBook Pro (14-inch, 2024)",
        "Mac17,2": "MacBook Pro (14-inch, M5)",
        "Mac17,6": "MacBook Pro (16-inch, M5 Pro or M5 Max)",
        "Mac17,7": "MacBook Pro (14-inch, M5 Pro or M5 Max)",
        "Mac17,8": "MacBook Pro (16-inch, M5 Pro or M5 Max)",
        "Mac17,9": "MacBook Pro (14-inch, M5 Pro or M5 Max)",
        // iMac
        "iMac20,1": "iMac (Retina 5K, 27-inch, 2020)",
        "iMac20,2": "iMac (Retina 5K, 27-inch, 2020)",
        "iMac21,1": "iMac (24-inch, M1, 2021)",
        "iMac21,2": "iMac (24-inch, M1, 2021)",
        "Mac15,4": "iMac (24-inch, 2023)",
        "Mac15,5": "iMac (24-inch, 2023)",
        "Mac16,2": "iMac (24-inch, 2024)",
        "Mac16,3": "iMac (24-inch, 2024)",
        // Mac mini
        "Macmini8,1": "Mac mini (2018)",
        "Macmini9,1": "Mac mini (M1, 2020)",
        "Mac14,3": "Mac mini (2023, M2)",
        "Mac14,12": "Mac mini (2023, M2 Pro)",
        "Mac16,10": "Mac mini (2024)",
        "Mac16,11": "Mac mini (2024)",
        "Mac17,16": "Mac mini (M5 Pro, 2026)",
        "Mac18,5": "Mac mini (M6, 2026)",
        // Mac Studio
        "Mac13,1": "Mac Studio (M1 Max, 2022)",
        "Mac13,2": "Mac Studio (M1 Ultra, 2022)",
        "Mac14,13": "Mac Studio (M2 Max, 2023)",
        "Mac14,14": "Mac Studio (M2 Ultra, 2023)",
        "Mac15,14": "Mac Studio (M3 Ultra, 2025)",
        "Mac16,9": "Mac Studio (M4 Max, 2025)",
        "Mac17,14": "Mac Studio (M5 Max, 2026)",
        "Mac17,15": "Mac Studio (M5 Ultra, 2026)",
        // Mac Pro
        "Mac14,8": "Mac Pro (2023)",
    ]

    static func name(for identifier: String) -> String? { names[identifier] }
}
