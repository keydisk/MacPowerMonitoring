import Foundation

public final class RiskEvaluator: @unchecked Sendable {
    private var disconnectEvents: [Date] = []
    private var lastConnected: Bool? = nil
    private var lastTelemetryErrorCount: Int? = nil
    private let lock = NSLock()

    public init() {}

    public func evaluate(sample: PowerTelemetry) -> RiskEvaluation {
        lock.lock()
        defer { lock.unlock() }

        let now = sample.timestamp
        let conn = sample.externalConnected

        // 순간 단절(Intermittent Disconnection) 감지
        if let last = lastConnected, last && !conn {
            disconnectEvents.append(now)
        }
        lastConnected = conn

        // 최근 60초 이내 단절 이벤트만 유지
        disconnectEvents.removeAll { now.timeIntervalSince($0) > 60.0 }
        let recentDisconnects = disconnectEvents.count

        var score = 0
        var alerts: [AlertItem] = []

        // 1. 단절 빈도 검사 (쇼트/아크 발생 위험)
        if recentDisconnects >= 2 {
            score += 45
            alerts.append(AlertItem(
                timestamp: now,
                level: .danger,
                title: "잦은 전원 연결 해제 (접촉 불량 의심)",
                message: "최근 1분간 어댑터 연결 끊김이 \(recentDisconnects)회 감지되었습니다. 케이블과 포트의 접촉 상태를 확인하세요."
            ))
        } else if !conn {
            score += 15
            alerts.append(AlertItem(
                timestamp: now,
                level: .safe,
                title: "배터리 전원 사용 중",
                message: "AC 충전기가 연결되어 있지 않아 내장 배터리로 구동 중입니다."
            ))
        }

        // 2. 전압 강하율 검사 (정격 전압 대비 인입 전압 결함 지표)
        if let dropPct = sample.voltageDropPct {
            if dropPct > 7.0 {
                score += 50
                alerts.append(AlertItem(
                    timestamp: now,
                    level: .danger,
                    title: "위험 수준의 전압 강하 감지",
                    message: String(format: "정격 대비 전압 강하율이 %.2f%%로 위험 기준(7%%)을 초과했습니다. 케이블/충전기 과열 위험이 있습니다.", dropPct)
                ))
            } else if dropPct > 4.5 {
                score += 25
                alerts.append(AlertItem(
                    timestamp: now,
                    level: .caution,
                    title: "주의 수준의 전압 강하 감지",
                    message: String(format: "정격 대비 전압 강하율이 %.2f%%입니다. 접촉 저항이나 케이블 품질을 확인하세요.", dropPct)
                ))
            }
        }

        // 3. 충전기 부하율 검사 (과부하 판정)
        if let loadPct = sample.adapterLoadPct, loadPct > 100.0 {
            score += 30
            alerts.append(AlertItem(
                timestamp: now,
                level: .caution,
                title: "충전기 정격 용량 초과 (과부하 공급)",
                message: String(format: "현재 소비 전력이 어댑터 정격의 %.1f%%입니다. 충전기 발열이 심해질 수 있습니다.", loadPct)
            ))
        }

        // 4. 텔레메트리 에러 검사
        // PowerTelemetryErrorCount 는 부팅 이후 누적값이므로, 앱 실행 중 새로 증가한 경우만 경고한다.
        let newTelemetryErrors = max(0, sample.telemetryErrors - (lastTelemetryErrorCount ?? sample.telemetryErrors))
        lastTelemetryErrorCount = sample.telemetryErrors
        if newTelemetryErrors > 0 {
            score += 20
            alerts.append(AlertItem(
                timestamp: now,
                level: .caution,
                title: "전력 텔레메트리 에러 증가",
                message: "전력 측정 텔레메트리 에러가 새로 \(newTelemetryErrors)건 기록되었습니다 (부팅 후 누적 \(sample.telemetryErrors)건)."
            ))
        }

        // 5. 저속 충전 플래그 검사
        if sample.slowChargingReason > 0 {
            score += 20
            alerts.append(AlertItem(
                timestamp: now,
                level: .caution,
                title: "저속 충전 모드 제한 활성화",
                message: "안전 보호 알고리즘 또는 전원 용량 부족으로 충전 속도가 강제 제한되었습니다."
            ))
        }

        // 점수 클램프 (0 ~ 100)
        let finalScore = max(0, min(100, score))
        let level: RiskLevel
        if finalScore >= 50 {
            level = .danger
        } else if finalScore >= 25 {
            level = .caution
        } else {
            level = .safe
        }

        return RiskEvaluation(
            score: finalScore,
            level: level,
            alerts: alerts,
            recentDisconnects: recentDisconnects
        )
    }
}
