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
        if isCharging { return "충전 중" }
        if !externalConnected { return "방전 중" }
        return fullyCharged ? "완충" : "충전 대기 (어댑터 전원 사용)"
    }
}

// ==============================================================================
// 2. 위험도(Risk) 및 경고 모델
// ==============================================================================
public enum RiskLevel: String, Sendable, CaseIterable {
    case safe = "SAFE"
    case caution = "CAUTION"
    case danger = "DANGER"

    public var title: String {
        switch self {
        case .safe: return "안전 (SAFE)"
        case .caution: return "주의 (CAUTION)"
        case .danger: return "위험 (DANGER)"
        }
    }

    public var color: Color {
        switch self {
        case .safe: return Color(red: 0.06, green: 0.73, blue: 0.51) // #10b981
        case .caution: return Color(red: 0.96, green: 0.62, blue: 0.04) // #f59e0b
        case .danger: return Color(red: 0.94, green: 0.27, blue: 0.27) // #ef4444
        }
    }

    public var glowColor: Color {
        color.opacity(0.35)
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
    public let score: Int // 0 (완전 안전) ~ 100 (극도로 위험)
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
