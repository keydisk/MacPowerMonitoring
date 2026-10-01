import Foundation

struct GPUStatistics: Sendable {
    let usage: Double?
    let renderer: Double?
    let tiler: Double?

    init?(properties: [String: Any]) {
        func percent(_ key: String) -> Double? {
            guard let value = (properties[key] as? NSNumber)?.doubleValue,
                  value.isFinite, (0...100).contains(value) else { return nil }
            return value
        }
        usage = percent("Device Utilization %")
        renderer = percent("Renderer Utilization %")
        tiler = percent("Tiler Utilization %")
        guard usage != nil || renderer != nil || tiler != nil else { return nil }
    }
}
