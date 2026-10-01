import Foundation
import SwiftUI

@main
struct ExtendedTelemetryCheck {
    @MainActor static func main() {
        let service = TelemetryService()
        service.stop()
        if let memory = MemoryStatistics.read() {
            assert(memory.totalBytes > 0)
            assert((0...100).contains(memory.usagePercent))
            assert(memory.swapUsedBytes.map { $0 >= 0 } ?? true)
            print("Memory: \(memory.usagePercent)%, swap: \(memory.swapUsedBytes ?? -1) bytes")
        } else {
            assertionFailure("Memory counters unavailable")
        }
        let timestamp = Date()
        let charging = service.parseIOKitBattery([
            "ExternalConnected": true,
            "IsCharging": true,
            "Voltage": 12500,
            "InstantAmperage": 2000,
            "PowerTelemetryData": ["SystemVoltageIn": 19900, "SystemPowerIn": 67100, "SystemLoad": 42100],
            "PackTelemetry": ["Temperature": 3000],
            "CellVoltages": [NSNumber(value: 4160), NSNumber(value: 4170)],
            "BatteryData": ["DesignCapacity": 6000, "NominalChargeCapacity": 5400],
            "PowerOutDetails": [["Watts": 1500], ["Watts": 500]]
        ], timestamp: timestamp)
        assert(charging.suppliedPowerW == 67.1)
        assert(charging.systemLoadW == 42.1)
        assert(charging.batteryPowerW == 25)
        assert(abs(charging.batteryTemperatureC! - 26.85) < 0.001)
        assert(charging.cellVoltagesV == [4.16, 4.17])
        assert(charging.batteryHealthPct == 90)
        assert(charging.usbOutputPowerW == 2)

        let discharge = service.parseIOKitBattery([
            "Voltage": 12000,
            "Amperage": NSNumber(value: UInt64(bitPattern: -1000))
        ], timestamp: timestamp)
        assert(discharge.batteryPowerW == -12)
        assert(discharge.suppliedPowerW == nil)
        assert(discharge.systemLoadW == nil)
        let missing = service.parseIOKitBattery([:], timestamp: timestamp)
        assert(missing.batteryPowerW == nil && missing.batteryTemperatureC == nil)
        assert(missing.cellVoltagesV.isEmpty)
        assert(CPUSampler.usage(previous: [10, 10, 10, 10], current: [20, 20, 80, 20]) == 30)
        assert(CPUSampler.usage(previous: [0, 0, 0, 0], current: [0, 0, 0, 0]) == nil)
        assert(CPUSampler.usage(previous: [UInt32.max, 0, 0, 0], current: [0, 0, 1, 0]) == 50)
        assert(GPUStatistics(properties: [:]) == nil)
        assert(GPUStatistics(properties: ["Device Utilization %": 101]) == nil)
        assert(GPUStatistics(properties: ["Device Utilization %": 0])?.usage == 0)
        assert(GPUStatistics(properties: ["Device Utilization %": 36, "Renderer Utilization %": 35, "Tiler Utilization %": 18])?.renderer == 35)
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 90), CGPoint(x: 20, y: 10), CGPoint(x: 30, y: 10)]
        var segment = 0
        SmoothChartPath.make(points).forEach { element in
            if case let .curve(to: end, control1: c1, control2: c2) = element {
                let low = min(points[segment].y, points[segment + 1].y)
                let high = max(points[segment].y, points[segment + 1].y)
                assert((low...high).contains(c1.y) && (low...high).contains(c2.y))
                assert(end == points[segment + 1])
                segment += 1
            }
        }
        assert(segment == points.count - 1)
        assert(SmoothChartPath.make([]).isEmpty)
        print("ExtendedTelemetryCheck passed")
    }
}
