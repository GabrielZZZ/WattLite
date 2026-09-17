import Foundation

@main
struct Probe {
    static func main() {
        let connection = smc_open()
        defer { smc_close(connection) }
        print("SMC connection:", connection)
        var count = 0.0
        if smc_read(connection, "#KEY", &count) != 0 {
            print("Key count:", count)
            for index in 0..<min(Int(count), 20000) {
                var key = [CChar](repeating: 0, count: 5)
                if smc_key_at(connection, UInt32(index), &key) != 0 {
                    let name = String(cString: key)
                    if name.hasPrefix("B0") || name.hasPrefix("PD") || name.hasPrefix("PB") || name.hasPrefix("ID") || name.hasPrefix("VD") || name.hasPrefix("IB") || name.hasPrefix("VB") || name == "PSTR" {
                        var value = 0.0
                        if smc_read(connection, name, &value) != 0 { print(name, value) }
                    }
                }
            }
        }
    }
}
