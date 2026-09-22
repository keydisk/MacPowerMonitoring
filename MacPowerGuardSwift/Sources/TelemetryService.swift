import Foundation
import AppKit
import Combine
import IOKit

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
    private let maxPoints: Int = 600 // 1초 주기 x 600개 = 최근 10분(600초) 파형 보관

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
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0초 주기
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

    private func handleNewSample(_ sample: PowerTelemetry?) {
        guard let sample else {
            // 배터리 서비스가 없는 Mac(mini/Studio/iMac/Pro) 또는 읽기 실패
            self.isConnected = false
            return
        }
        let evaluation = evaluator.evaluate(sample: sample)
        self.telemetry = sample
        self.risk = evaluation
        self.packetCount += 1
        self.isConnected = true

        let now = sample.timestamp
        let timeStr = Self.timeFormatter.string(from: now)
        if sample.systemPowerW >= 0.0 {
            powerHistory.append(ChartPoint(time: now, timeStr: timeStr, value: sample.systemPowerW))
            if powerHistory.count > maxPoints {
                powerHistory.removeFirst(powerHistory.count - maxPoints)
            }
        }

        if sample.systemVoltageV > 0.0 {
            voltageHistory.append(ChartPoint(time: now, timeStr: timeStr, value: sample.systemVoltageV))
            if voltageHistory.count > maxPoints {
                voltageHistory.removeFirst(voltageHistory.count - maxPoints)
            }
        }

        // 새로운 위험 알림이 있으면 로그에 축적 (1초 주기에 맞춰 10초 이내 중복 방지)
        for alert in evaluation.alerts {
            if !alertLog.contains(where: { $0.title == alert.title && abs($0.timestamp.timeIntervalSince(alert.timestamp)) < 10.0 }) {
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

    /// AppleSmartBattery 서비스가 없거나(데스크톱 Mac) 읽기에 실패하면 nil.
    /// 실패를 "외부 전원 끊김"으로 오인하지 않도록 기본값 샘플을 만들지 않는다.
    nonisolated private func fetchSample() -> PowerTelemetry? {
        // ioreg 프로세스 실행 대신 IOKit 레지스트리를 직접 읽는다 (App Sandbox 호환, 800ms 마다 프로세스 생성 비용 제거).
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let b = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return parseIOKitBattery(b, timestamp: Date())
    }

    nonisolated private func parseIOKitBattery(_ b: [String: Any], timestamp: Date) -> PowerTelemetry {
        func bool(_ v: Any?) -> Bool { (v as? Bool) ?? ((v as? NSNumber)?.intValue == 1) }
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

        let externalConnected = bool(b["ExternalConnected"])
        let isCharging = bool(b["IsCharging"])
        let fullyCharged = bool(b["FullyCharged"])

        // 1. Adapter Details — 연결 해제 후에도 AdapterDetails 가 남아 있는 경우가 있어 외부 전원 연결 시에만 사용
        var adapterWatts: Double? = nil
        var adapterVoltageV: Double? = nil
        var adapterCurrentA: Double? = nil
        var adapterDesc = "Unknown"
        var familyCode = "-"

        if externalConnected, let adapter = b["AdapterDetails"] as? [String: Any] {
            if let w = num(adapter["Watts"]), w > 0 { adapterWatts = w }
            // AdapterVoltage/Current 는 PD 협상된 정격(최대) 값이며 실측값이 아님
            if let v = num(adapter["AdapterVoltage"]), v > 0 { adapterVoltageV = v / 1000.0 }
            if let a = num(adapter["Current"]), a > 0 { adapterCurrentA = a / 1000.0 }
            if let d = adapter["Description"] as? String { adapterDesc = d }
            if let fc = adapter["FamilyCode"] as? NSNumber {
                familyCode = String(format: "0x%08x", fc.uint32Value)
            }
        }

        // 2. Power Telemetry Data (Apple Silicon & modern Intel Macs) — 단위: mV, mA, mW
        var systemVoltageV: Double = 0.0
        var systemCurrentA: Double = 0.0
        var systemPowerW: Double = 0.0
        var systemLoadW: Double = 0.0
        var telemetryErrors: Int = 0

        if let pt = b["PowerTelemetryData"] as? [String: Any] {
            systemVoltageV = (num(pt["SystemVoltageIn"]) ?? 0) / 1000.0
            systemCurrentA = (num(pt["SystemCurrentIn"]) ?? 0) / 1000.0
            systemPowerW = (num(pt["SystemPowerIn"]) ?? 0) / 1000.0
            systemLoadW = (num(pt["SystemLoad"]) ?? 0) / 1000.0
            telemetryErrors = (pt["PowerTelemetryErrorCount"] as? NSNumber)?.intValue ?? 0
        }

        let isInputMeasured = externalConnected && systemVoltageV > 0
        if !isInputMeasured {
            // 배터리 구동(또는 텔레메트리 미지원) 시: 배터리 팩 전압/전류로 대체.
            // Amperage 는 부호 있는 mA (방전 시 음수) — 큰 UInt64 로 보일 수 있어 Int64 로 해석
            systemVoltageV = (num(b["Voltage"]) ?? 0) / 1000.0
            let amperage = (b["Amperage"] as? NSNumber)?.int64Value ?? 0
            systemCurrentA = abs(Double(amperage)) / 1000.0
            systemPowerW = systemLoadW > 0 ? systemLoadW : systemVoltageV * systemCurrentA
        }

        // 3. Charger Data
        var slowChargingReason = 0
        var thermalLimitedSec = 0
        if let cd = b["ChargerData"] as? [String: Any] {
            if let scr = cd["SlowChargingReason"] as? NSNumber { slowChargingReason = scr.intValue }
            if let tls = cd["TimeChargingThermallyLimited"] as? NSNumber { thermalLimitedSec = tls.intValue }
        }

        // 4. Battery Level / Health / Cycles
        // Apple Silicon: CurrentCapacity/MaxCapacity 는 이미 % (MaxCapacity == 100)
        // Intel: 두 값 모두 mAh → 비율로 계산해야 두 플랫폼 모두 올바른 충전량(%)이 됨
        let bd = b["BatteryData"] as? [String: Any] ?? [:]
        var batteryLevel: Int? = nil
        if let cur = num(b["CurrentCapacity"]) ?? num(bd["CurrentCapacity"]),
           let max = num(b["MaxCapacity"]) ?? num(bd["MaxCapacity"]), max > 0 {
            batteryLevel = Int((cur / max * 100.0).rounded())
        }

        // 배터리 성능 최대치 = 공칭 완충 용량 / 설계 용량 (시스템 설정은 100% 로 상한 표시)
        var batteryHealth: Int? = nil
        let fullMah = num(bd["NominalChargeCapacity"]) ?? num(b["NominalChargeCapacity"])
            ?? num(b["AppleRawMaxCapacity"]) ?? num(bd["FullChargeCapacity"])
        let designMah = num(b["DesignCapacity"]) ?? num(bd["DesignCapacity"])
        if let full = fullMah, let design = designMah, design > 0 {
            batteryHealth = min(100, Int((full / design * 100.0).rounded()))
        }
        let cycleCount: Int? = (b["CycleCount"] as? NSNumber)?.intValue

        // 5. 전압 강하율 및 부하율 계산 — 어댑터 인입 실측값이 있을 때만 (배터리 전압과 비교하면 허위 경보)
        var voltageDropV: Double? = nil
        var voltageDropPct: Double? = nil
        if isInputMeasured, let aV = adapterVoltageV {
            let drop = aV - systemVoltageV
            voltageDropV = drop
            voltageDropPct = (drop / aV) * 100.0
        }

        var adapterLoadPct: Double? = nil
        if isInputMeasured, let aW = adapterWatts {
            adapterLoadPct = (systemPowerW / aW) * 100.0
        }

        return PowerTelemetry(
            timestamp: timestamp,
            externalConnected: externalConnected,
            isCharging: isCharging,
            fullyCharged: fullyCharged,
            isInputMeasured: isInputMeasured,
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
            batteryHealthPct: batteryHealth,
            batteryCycleCount: cycleCount,
            telemetryErrors: telemetryErrors,
            slowChargingReason: slowChargingReason,
            thermalLimitedSec: thermalLimitedSec,
            familyCode: familyCode
        )
    }
}
