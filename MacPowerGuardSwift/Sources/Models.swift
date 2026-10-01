import Foundation
import SwiftUI

// ==============================================================================
// 1. 하드웨어 전력 텔레메트리 데이터 모델
// ==============================================================================
public struct PowerTelemetry: Sendable {
    public let timestamp: Date
    public let externalConnected: Bool
    public let isCharging: Bool
    public let fullyCharged: Bool
    // true: systemVoltage/Current/Power 가 PowerTelemetryData 의 어댑터 인입 실측값
    // false: 배터리 팩 전압/전류 기반 대체값 (전압 강하율 계산에 쓰면 안 됨)
    public let isInputMeasured: Bool
    public let adapterWatts: Double?
    public let adapterVoltageV: Double?
    public let adapterCurrentA: Double?
    public let adapterDesc: String
    public let systemVoltageV: Double
    public let systemCurrentA: Double
    public let systemPowerW: Double
    public let voltageDropV: Double?
    public let voltageDropPct: Double?
    public let adapterLoadPct: Double?
    public let batteryLevelPct: Int?
    public let batteryHealthPct: Int?  // 설계 용량 대비 최대 용량 (시스템 설정의 "최대 용량")
    public let batteryCycleCount: Int?
    public let telemetryErrors: Int  // PowerTelemetryErrorCount (부팅 후 누적값)
    public let slowChargingReason: Int
    public let thermalLimitedSec: Int
    public let familyCode: String
    public var systemLoadW: Double? = nil
    public var suppliedPowerW: Double? = nil
    public var batteryPowerW: Double? = nil // + 충전, - 방전 (팩 전압 × signed 전류)
    public var batteryVoltageV: Double? = nil
    public var batteryTemperatureC: Double? = nil
    public var cellVoltagesV: [Double] = []
    public var designCapacityMah: Double? = nil
    public var fullCapacityMah: Double? = nil
    public var usbOutputPowerW: Double? = nil

    public init(
        timestamp: Date = Date(),
        externalConnected: Bool = false,
        isCharging: Bool = false,
        fullyCharged: Bool = false,
        isInputMeasured: Bool = false,
        adapterWatts: Double? = nil,
        adapterVoltageV: Double? = nil,
        adapterCurrentA: Double? = nil,
        adapterDesc: String = "Unknown",
        systemVoltageV: Double = 0.0,
        systemCurrentA: Double = 0.0,
        systemPowerW: Double = 0.0,
        voltageDropV: Double? = nil,
        voltageDropPct: Double? = nil,
        adapterLoadPct: Double? = nil,
        batteryLevelPct: Int? = nil,
        batteryHealthPct: Int? = nil,
        batteryCycleCount: Int? = nil,
        telemetryErrors: Int = 0,
        slowChargingReason: Int = 0,
        thermalLimitedSec: Int = 0,
        familyCode: String = "-"
    ) {
        self.timestamp = timestamp
        self.externalConnected = externalConnected
        self.isCharging = isCharging
        self.fullyCharged = fullyCharged
        self.isInputMeasured = isInputMeasured
        self.adapterWatts = adapterWatts
        self.adapterVoltageV = adapterVoltageV
        self.adapterCurrentA = adapterCurrentA
        self.adapterDesc = adapterDesc
        self.systemVoltageV = systemVoltageV
        self.systemCurrentA = systemCurrentA
        self.systemPowerW = systemPowerW
        self.voltageDropV = voltageDropV
        self.voltageDropPct = voltageDropPct
        self.adapterLoadPct = adapterLoadPct
        self.batteryLevelPct = batteryLevelPct
        self.batteryHealthPct = batteryHealthPct
        self.batteryCycleCount = batteryCycleCount
        self.telemetryErrors = telemetryErrors
        self.slowChargingReason = slowChargingReason
        self.thermalLimitedSec = thermalLimitedSec
        self.familyCode = familyCode
    }
}

extension PowerTelemetry {
    /// 연결되어 있지만 충전하지 않는 경우(최적화 충전, 80% 제한 등)를 "완충"으로 오표시하지 않는다.
    public var chargeStateText: String {
        if isCharging { return String(localized: "충전 중") }
        if !externalConnected { return String(localized: "방전 중") }
        return fullyCharged ? String(localized: "완충") : String(localized: "충전 대기 (어댑터 전원 사용)")
    }
}

// ==============================================================================
// 2. 이벤트 분류 및 알림 모델
// ==============================================================================
public enum RiskLevel: String, Sendable, CaseIterable {
    case safe = "SAFE"
    case caution = "CAUTION"
    case danger = "DANGER"

    public var title: String {
        switch self {
        case .safe: return String(localized: "연결 정보")
        case .caution: return String(localized: "부하 변화")
        case .danger: return String(localized: "전압 변화")
        }
    }

    public var color: Color {
        switch self {
        case .safe, .caution, .danger: return .secondary
        }
    }

    public var symbol: String {
        switch self {
        case .safe, .caution, .danger: return "waveform.path"
        }
    }
}

public struct AlertItem: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: RiskLevel
    public let title: String
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: RiskLevel,
        title: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.title = title
        self.message = message
    }
}

public struct RiskEvaluation: Sendable {
    public let score: Int // 0 ~ 100
    public let level: RiskLevel
    public let alerts: [AlertItem]
    public let recentDisconnects: Int

    public init(
        score: Int = 0,
        level: RiskLevel = .safe,
        alerts: [AlertItem] = [],
        recentDisconnects: Int = 0
    ) {
        self.score = score
        self.level = level
        self.alerts = alerts
        self.recentDisconnects = recentDisconnects
    }
}

// ==============================================================================
// 3. 실시간 파형 시계열 포인트 모델 (Charts)
// ==============================================================================
public struct ChartPoint: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let timeStr: String
    public let value: Double

    public init(id: UUID = UUID(), time: Date = Date(), timeStr: String = "", value: Double = 0.0) {
        self.id = id
        self.time = time
        self.timeStr = timeStr
        self.value = value
    }
}
