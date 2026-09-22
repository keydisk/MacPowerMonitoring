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

    // 시간 범위 및 LTTB 샘플링 상태
    @Published public var timeRangeOption: TimeRangeOption = .last10Min {
        didSet {
            updateDisplayHistories()
        }
    }
    @Published public var customStartDate: Date = Date().addingTimeInterval(-600) {
        didSet {
            if timeRangeOption == .custom {
                validateCustomRange()
                updateDisplayHistories()
            }
        }
    }
    @Published public var customEndDate: Date = Date() {
        didSet {
            if timeRangeOption == .custom {
                validateCustomRange()
                updateDisplayHistories()
            }
        }
    }
    @Published public var timeSpanDescription: String = "최근 10분"
    @Published public var isDownsampled: Bool = false
    @Published public var totalRawPoints: Int = 0
    @Published public var currentDisplayCount: Int = 0

    // 내부 원본 보관 버퍼 (1초 x 86,400개 = 최대 24시간 연속 데이터 보관)
    private var rawPowerHistory: [ChartPoint] = []
    private var rawVoltageHistory: [ChartPoint] = []
    private let maxRawPoints: Int = 86400

    private let evaluator = RiskEvaluator()
    private var timerTask: Task<Void, Never>?
    private var lastRiskLevel: RiskLevel = .safe

    /// Mac 시스템 부팅 시각
    public var macBootDate: Date {
        Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
    }

    /// Mac 시스템 가동 시간 (Uptime) 문자열
    public var macUptimeString: String {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let days = uptime / 86400
        let hours = (uptime % 86400) / 3600
        let minutes = (uptime % 3600) / 60
        if days > 0 {
            return "\(days)일 \(hours)시간 \(minutes)분"
        } else if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        } else {
            return "\(minutes)분"
        }
    }

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

    public func selectTimeRange(_ option: TimeRangeOption) {
        self.timeRangeOption = option
        let now = Date()
        switch option {
        case .last10Min:
            customStartDate = now.addingTimeInterval(-600)
            customEndDate = now
        case .last30Min:
            customStartDate = now.addingTimeInterval(-1800)
            customEndDate = now
        case .last1Hour:
            customStartDate = now.addingTimeInterval(-3600)
            customEndDate = now
        case .sinceBoot:
            customStartDate = macBootDate
            customEndDate = now
        case .custom:
            validateCustomRange()
        }
        updateDisplayHistories()
    }

    private func validateCustomRange() {
        let now = Date()
        let boot = macBootDate
        if customStartDate < boot {
            customStartDate = boot
        }
        if customEndDate > now {
            customEndDate = now
        }
        // 최소 10분(600초) 표시 범위 보장
        if customEndDate.timeIntervalSince(customStartDate) < 600 {
            if customStartDate.addingTimeInterval(600) <= now {
                customEndDate = customStartDate.addingTimeInterval(600)
            } else {
                customStartDate = customEndDate.addingTimeInterval(-600)
            }
        }
    }

    public func updateDisplayHistories() {
        let now = Date()
        var start: Date
        var end: Date

        switch timeRangeOption {
        case .last10Min:
            start = now.addingTimeInterval(-600)
            end = now
            timeSpanDescription = "최근 10분"
        case .last30Min:
            start = now.addingTimeInterval(-1800)
            end = now
            timeSpanDescription = "최근 30분"
        case .last1Hour:
            start = now.addingTimeInterval(-3600)
            end = now
            timeSpanDescription = "최근 1시간"
        case .sinceBoot:
            start = macBootDate
            end = now
            timeSpanDescription = "맥 실행 전체 (\(macUptimeString))"
        case .custom:
            validateCustomRange()
            start = customStartDate
            end = customEndDate
            let spanSec = Int(end.timeIntervalSince(start))
            let spanH = spanSec / 3600
            let spanM = (spanSec % 3600) / 60
            if spanH > 0 {
                timeSpanDescription = "\(spanH)시간 \(spanM)분 선택"
            } else {
                timeSpanDescription = "\(spanM)분 선택"
            }
        }

        // 시간 범위에 해당하는 원본 데이터 필터링
        let filteredPower = rawPowerHistory.filter { $0.time >= start && $0.time <= end }
        let filteredVoltage = rawVoltageHistory.filter { $0.time >= start && $0.time <= end }

        self.totalRawPoints = filteredPower.count

        // 화면 표시에 최적화된 300개 포인트로 LTTB 알고리즘 다운샘플링 적용
        let target = 300
        if filteredPower.count > target {
            self.powerHistory = LTTBDownsampler.downsample(filteredPower, targetCount: target)
            self.isDownsampled = true
        } else {
            self.powerHistory = filteredPower
            self.isDownsampled = false
        }

        if filteredVoltage.count > target {
            self.voltageHistory = LTTBDownsampler.downsample(filteredVoltage, targetCount: target)
        } else {
            self.voltageHistory = filteredVoltage
        }

        self.currentDisplayCount = self.powerHistory.count
    }

    private func handleNewSample(_ sample: PowerTelemetry?) {
        guard let sample else {
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
            rawPowerHistory.append(ChartPoint(time: now, timeStr: timeStr, value: sample.systemPowerW))
            if rawPowerHistory.count > maxRawPoints {
                rawPowerHistory.removeFirst(rawPowerHistory.count - maxRawPoints)
            }
        }

        if sample.systemVoltageV > 0.0 {
            rawVoltageHistory.append(ChartPoint(time: now, timeStr: timeStr, value: sample.systemVoltageV))
            if rawVoltageHistory.count > maxRawPoints {
                rawVoltageHistory.removeFirst(rawVoltageHistory.count - maxRawPoints)
            }
        }

        // 최신 샘플 기반 표시 차트 버퍼 갱신
        updateDisplayHistories()

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
