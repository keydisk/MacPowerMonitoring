import SwiftUI

public struct MetricCardView: View {
    @ObservedObject var service: TelemetryService

    public init(service: TelemetryService) {
        self.service = service
    }

    public var body: some View {
        let t = service.telemetry
        HStack(spacing: 16) {
            // 1. 실시간 소비 전력
            card("실시간 소비 전력",
                 value: t?.systemLoadW.map { String(format: "%.1f", $0) } ?? "--", unit: "W",
                 progress: (t?.adapterLoadPct ?? 0.0) / 100.0, tint: .blue) {
                if let supplied = t?.suppliedPowerW {
                    Text("공급 전력: \(supplied, specifier: "%.1f") W")
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

            if let dropPct = t?.voltageDropPct {
                card("전압 안정도",
                     value: String(format: "%.2f", dropPct), unit: "%",
                     progress: max(0, 1 - dropPct / 100), tint: .blue) {
                    Text("정격 대비 전압 강하")
                    if let t, t.isInputMeasured, let adapterVoltage = t.adapterVoltageV {
                        Text("정격 \(adapterVoltage, specifier: "%.1f") V 대비 인입 \(t.systemVoltageV, specifier: "%.2f") V")
                    }
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

            if let loadPct = t?.adapterLoadPct {
                card("어댑터 부하율",
                     value: String(format: "%.1f", loadPct), unit: "%",
                     progress: loadPct / 100, tint: .blue) {
                    if let watts = t?.adapterWatts {
                        Text("어댑터 정격: \(watts, specifier: "%.0f") W")
                    }
                }
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
