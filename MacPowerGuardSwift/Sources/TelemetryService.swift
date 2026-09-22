import Foundation
import AppKit
import Combine

@MainActor
public final class TelemetryService: ObservableObject {
    @Published public var telemetry: PowerTelemetry?
    @Published public var risk: RiskEvaluation = RiskEvaluation()
    @Published public var powerHistory: [ChartPoint] = []
    @Published public var voltageHistory: [ChartPoint] = []
    @Published public var alertLog: [AlertItem] = []
    @Published public var packetCount: Int = 0
    @Published public var isPaused: Bool = false
    @Published public var soundEnabled: Bool = false
    @Published public var isConnected: Bool = true

    private let evaluator = RiskEvaluator()
    private var timerTask: Task<Void, Never>?
    private var lastRiskLevel: RiskLevel = .safe
    private let maxPoints: Int = 60

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    public init() {
        start()
    }

    public func start() {
        guard timerTask == nil else { return }
        timerTask = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                let isPaused = await self.isPaused
                if !isPaused {
                    let sample = self.fetchSample()
                    await self.handleNewSample(sample)
                }
                try? await Task.sleep(nanoseconds: 800_000_000) // 800ms
            }
        }
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    public func togglePause() {
        isPaused.toggle()
    }

    public func toggleSound() {
        soundEnabled.toggle()
        if soundEnabled {
            NSSound.beep()
        }
    }

    private func handleNewSample(_ sample: PowerTelemetry) {
        let evaluation = evaluator.evaluate(sample: sample)
        self.telemetry = sample
        self.risk = evaluation
        self.packetCount += 1
        self.isConnected = true

        let now = sample.timestamp
        let timeStr = Self.timeFormatter.string(from: now)
        powerHistory.append(ChartPoint(time: now, timeStr: timeStr, value: sample.systemPowerW))
        if powerHistory.count > maxPoints {
            powerHistory.removeFirst(powerHistory.count - maxPoints)
        }

        voltageHistory.append(ChartPoint(time: now, timeStr: timeStr, value: sample.systemVoltageV))
        if voltageHistory.count > maxPoints {
            voltageHistory.removeFirst(voltageHistory.count - maxPoints)
        }

        // 새로운 위험 알림이 있으면 로그에 축적
        for alert in evaluation.alerts {
            if !alertLog.contains(where: { $0.title == alert.title && abs($0.timestamp.timeIntervalSince(alert.timestamp)) < 5.0 }) {
                alertLog.insert(alert, at: 0)
            }
        }
        if alertLog.count > 50 {
            alertLog.removeLast(alertLog.count - 50)
        }

        // 위험 단계 상승 시 경고음
        if soundEnabled && evaluation.level != .safe && evaluation.level != lastRiskLevel {
            NSSound.beep()
        }
        lastRiskLevel = evaluation.level
    }

    nonisolated private func fetchSample() -> PowerTelemetry {
        let now = Date()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        proc.arguments = ["-arn", "AppleSmartBattery"]
        let pipe = Pipe()
        proc.standardOutput = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]],
               let b = plist.first {
                return parseIOKitBattery(b, timestamp: now)
            }
        } catch {
            // Error executing ioreg
        }

        return PowerTelemetry(timestamp: now)
    }

    nonisolated private func parseIOKitBattery(_ b: [String: Any], timestamp: Date) -> PowerTelemetry {
        let externalConnected = (b["ExternalConnected"] as? Bool) ?? ((b["ExternalConnected"] as? Int) == 1)
        let isCharging = (b["IsCharging"] as? Bool) ?? ((b["IsCharging"] as? Int) == 1)

        // 1. Adapter Details
        var adapterWatts: Double? = nil
        var adapterVoltageV: Double? = nil
        var adapterCurrentA: Double? = nil
        var adapterDesc = "Unknown"
        var familyCode = "-"

        if let adapter = b["AdapterDetails"] as? [String: Any] {
            if let w = adapter["Watts"] as? NSNumber { adapterWatts = w.doubleValue }
            if let v = adapter["AdapterVoltage"] as? NSNumber { adapterVoltageV = v.doubleValue / 1000.0 }
            if let a = adapter["Current"] as? NSNumber { adapterCurrentA = a.doubleValue / 1000.0 }
            if let d = adapter["Description"] as? String { adapterDesc = d }
            if let fc = adapter["FamilyCode"] as? NSNumber {
                familyCode = String(format: "0x%08x", fc.uint32Value)
            }
        }

        // 2. Power Telemetry Data (Apple Silicon & modern Intel Macs)
        var systemVoltageV: Double = 0.0
        var systemCurrentA: Double = 0.0
        var systemPowerW: Double = 0.0
        var telemetryErrors: Int = 0

        if let pt = b["PowerTelemetryData"] as? [String: Any] {
            if let v = pt["SystemVoltageIn"] as? NSNumber { systemVoltageV = v.doubleValue / 1000.0 }
            if let a = pt["SystemCurrentIn"] as? NSNumber { systemCurrentA = a.doubleValue / 1000.0 }
            if let w = pt["SystemPowerIn"] as? NSNumber { systemPowerW = w.doubleValue / 1000.0 }
            if let err = pt["PowerTelemetryErrorCount"] as? NSNumber { telemetryErrors = err.intValue }
        }

        // 텔레메트리 데이터가 없거나 0일 때 배터리 기본 전압/전류로 대체
        if systemVoltageV == 0.0, let v = b["Voltage"] as? NSNumber {
            systemVoltageV = v.doubleValue / 1000.0
        }
        if systemCurrentA == 0.0, let a = b["Amperage"] as? NSNumber {
            systemCurrentA = abs(a.doubleValue) / 1000.0
        }
        if systemPowerW == 0.0 {
            systemPowerW = systemVoltageV * systemCurrentA
        }

        // 3. Charger Data
        var slowChargingReason = 0
        var thermalLimitedSec = 0
        if let cd = b["ChargerData"] as? [String: Any] {
            if let scr = cd["SlowChargingReason"] as? NSNumber { slowChargingReason = scr.intValue }
            if let tls = cd["TimeChargingThermallyLimited"] as? NSNumber { thermalLimitedSec = tls.intValue }
        }

        // 4. Battery Capacity & Cycles
        var batteryLevel: Int? = (b["CurrentCapacity"] as? NSNumber)?.intValue
        var batteryMaxCap: Int? = (b["MaxCapacity"] as? NSNumber)?.intValue
        let cycleCount: Int? = (b["CycleCount"] as? NSNumber)?.intValue

        if let bd = b["BatteryData"] as? [String: Any] {
            if let cur = bd["CurrentCapacity"] as? NSNumber { batteryLevel = cur.intValue }
            if let max = bd["MaxCapacity"] as? NSNumber { batteryMaxCap = max.intValue }
        }

        // 5. 전압 강하율 및 부하율 계산
        var voltageDropV: Double? = nil
        var voltageDropPct: Double? = nil
        if let aV = adapterVoltageV, aV > 0, systemVoltageV > 0 {
            let drop = aV - systemVoltageV
            voltageDropV = drop
            voltageDropPct = (drop / aV) * 100.0
        }

        var adapterLoadPct: Double? = nil
        if let aW = adapterWatts, aW > 0 {
            adapterLoadPct = (systemPowerW / aW) * 100.0
        }

        return PowerTelemetry(
            timestamp: timestamp,
            externalConnected: externalConnected,
            isCharging: isCharging,
            adapterWatts: adapterWatts,
            adapterVoltageV: adapterVoltageV,
            adapterCurrentA: adapterCurrentA,
            adapterDesc: adapterDesc,
            systemVoltageV: systemVoltageV,
            systemCurrentA: systemCurrentA,
            systemPowerW: systemPowerW,
            voltageDropV: voltageDropV,
            voltageDropPct: voltageDropPct,
            adapterLoadPct: adapterLoadPct,
            batteryLevelPct: batteryLevel,
            batteryMaxCapacityPct: batteryMaxCap,
            batteryCycleCount: cycleCount,
            telemetryErrors: telemetryErrors,
            slowChargingReason: slowChargingReason,
            thermalLimitedSec: thermalLimitedSec,
            familyCode: familyCode
        )
    }
}
