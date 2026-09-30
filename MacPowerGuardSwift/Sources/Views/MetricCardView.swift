import SwiftUI

public struct MetricCardView: View {
    @ObservedObject var service: TelemetryService

    public init(service: TelemetryService) {
        self.service = service
    }

    public var body: some View {
        let t = service.telemetry
        let r = service.risk
        let dropPct = t?.voltageDropPct ?? 0.0

        HStack(spacing: 16) {
            // 1. 실시간 소비 전력
            card("실시간 소비 전력",
                 value: String(format: "%.1f", t?.systemPowerW ?? 0.0), unit: "W",
                 progress: (t?.adapterLoadPct ?? 0.0) / 100.0, tint: .blue) {
                if let t, t.isInputMeasured {
                    Text("공급 전력: \(t.systemPowerW, specifier: "%.1f") W")
                } else {
                    Text("공급 전력: -- W")
                }
                if let watts = t?.adapterWatts, let load = t?.adapterLoadPct {
                    Text("어댑터: \(watts, specifier: "%.0f") W (부하 \(load, specifier: "%.1f")%)")
                } else if t?.externalConnected == true {
                    Text("어댑터 입력 측정값 없음 (배터리 기준 추정)")
                } else {
                    Text("배터리 전원 사용 중")
                }
            }

            // 2. 실시간 인입 전압 & 전압 강하 — RiskEvaluator 의 임계값(4.5% / 7%)과 동일
            card("실시간 인입 전압",
                 value: String(format: "%.2f", t?.systemVoltageV ?? 0.0), unit: "V",
                 progress: 1.0 - dropPct / 10.0,
                 tint: dropPct > 7.0 ? .red : (dropPct > 4.5 ? .orange : .green)) {
                if let aV = t?.adapterVoltageV, t?.voltageDropPct != nil {
                    Text("정격: \(aV, specifier: "%.1f") V (전압 강하: \(dropPct, specifier: "%.2f")%)")
                } else {
                    Text("배터리 팩 전압")
                }
            }

            // 3. 인입 전류 & 배터리
            card("인입 전류 & 배터리",
                 value: String(format: "%.2f", t?.systemCurrentA ?? 0.0), unit: "A",
                 progress: Double(t?.batteryLevelPct ?? 0) / 100.0, tint: .purple) {
                let levelStr = t?.batteryLevelPct.map { "\($0)%" } ?? "--"
                let cycleStr = t?.batteryCycleCount.map { String(localized: "\($0)회") } ?? "--"
                Text("배터리: \(levelStr) | 사이클: \(cycleStr) | \(t?.chargeStateText ?? "--")")
            }

            // 4. 전력 공급 위험도 판정
            card("전력 공급 위험도 판정",
                 value: "\(r.score)", unit: "/ 100",
                 progress: Double(r.score) / 100.0, tint: r.level.color,
                 badge: Label(r.level.title, systemImage: r.level.symbol).foregroundStyle(r.level.color)) {
                Group {
                    if r.score == 0 {
                        Text("모든 전원 센서 및 강하율 정상 (안전)")
                    } else if r.score < 25 {
                        Text("경미한 상태 변동 (정상 범위)")
                    } else if r.score < 50 {
                        Text("주의 필요 (충전기 상태 확인)")
                    } else {
                        Text("위험 감지! 즉시 충전기/포트 점검")
                    }
                }
                .foregroundStyle(r.score >= 25 ? r.level.color : .secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card<Footer: View>(
        _ title: LocalizedStringKey,
        value: String,
        unit: LocalizedStringKey,
        progress: Double,
        tint: Color,
        badge: some View = EmptyView(),
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                badge
            }
            .font(.subheadline)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                Text(unit)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: max(0.0, min(1.0, progress)))
                .tint(tint)

            footer()
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }
}
