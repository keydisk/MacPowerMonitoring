import SwiftUI

public struct MetricCardView: View {
    @ObservedObject var service: TelemetryService

    public init(service: TelemetryService) {
        self.service = service
    }

    public var body: some View {
        let t = service.telemetry
        let r = service.risk

        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            // 1. 실시간 소비 전력
            cardContainer {
                cardHeader(title: "실시간 소비 전력", icon: "bolt.fill", iconColor: Color(red: 0.02, green: 0.71, blue: 0.83)) // #06b6d4
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", t?.systemPowerW ?? 0.0))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("W")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(white: 0.6))
                }

                // Progress bar
                let maxW = max(t?.adapterWatts ?? 100.0, 1.0)
                let loadRatio = min(1.0, (t?.systemPowerW ?? 0.0) / maxW)
                progressBar(ratio: loadRatio, color: Color(red: 0.02, green: 0.71, blue: 0.83))

                HStack {
                    if let watts = t?.adapterWatts {
                        Text(String(format: "어댑터: %.0f W (부하 %.1f%%)", watts, (t?.adapterLoadPct ?? 0.0)))
                    } else {
                        Text("배터리 전원 사용 중")
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Color(white: 0.55))
            }

            // 2. 실시간 인입 전압 & 전압 강하
            cardContainer {
                cardHeader(title: "실시간 인입 전압", icon: "powerplug.fill", iconColor: Color(red: 0.06, green: 0.73, blue: 0.51)) // #10b981
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", t?.systemVoltageV ?? 0.0))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("V")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(white: 0.6))
                }

                // Drop ratio bar
                let dropPct = t?.voltageDropPct ?? 0.0
                let dropRatio = max(0.0, min(1.0, 1.0 - (dropPct / 10.0)))
                let barColor: Color = dropPct > 7.0 ? .red : (dropPct > 4.5 ? .yellow : Color(red: 0.06, green: 0.73, blue: 0.51))
                progressBar(ratio: dropRatio, color: barColor)

                HStack {
                    if let aV = t?.adapterVoltageV, aV > 0 {
                        Text(String(format: "정격: %.1f V (전압 강하: %.2f%%)", aV, dropPct))
                    } else {
                        Text("배터리 셀 전압")
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Color(white: 0.55))
            }

            // 3. 인입 전류 & 배터리
            cardContainer {
                cardHeader(title: "인입 전류 & 배터리", icon: "battery.100.bolt", iconColor: Color(red: 0.55, green: 0.36, blue: 0.96)) // #8b5cf6
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", t?.systemCurrentA ?? 0.0))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("A")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(white: 0.6))
                }

                // Battery level bar
                let battLevel = Double(t?.batteryLevelPct ?? 0) / 100.0
                progressBar(ratio: battLevel, color: Color(red: 0.55, green: 0.36, blue: 0.96))

                HStack {
                    let levelStr = t?.batteryLevelPct != nil ? "\(t!.batteryLevelPct!)%" : "--"
                    let cycleStr = t?.batteryCycleCount != nil ? "\(t!.batteryCycleCount!)회" : "--"
                    let chgStr = t?.isCharging == true ? "충전 중" : (t?.externalConnected == true ? "완충" : "방전")
                    Text("배터리: \(levelStr) | 사이클: \(cycleStr) | \(chgStr)")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Color(white: 0.55))
            }

            // 4. 전력 공급 위험도 판정
            cardContainer(borderHighlight: r.level.color.opacity(0.4), glow: r.level.glowColor) {
                HStack {
                    Text("전력 공급 위험도 판정")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(white: 0.6))
                        .textCase(.uppercase)
                    Spacer()
                    Text(r.level.title)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(r.level.color.opacity(0.18))
                        .foregroundColor(r.level.color)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(r.level.color.opacity(0.35), lineWidth: 1)
                        )
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(r.score)")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(r.level.color)
                    Text("/ 100")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                }

                // Risk progress bar
                let riskRatio = Double(r.score) / 100.0
                progressBar(ratio: riskRatio, color: r.level.color)

                HStack {
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
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(r.level.color)
            }
        }
    }

    private func cardContainer<Content: View>(
        borderHighlight: Color? = nil,
        glow: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.85)) // #0f172a
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderHighlight ?? Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: glow ?? Color.black.opacity(0.3), radius: glow != nil ? 10 : 6, x: 0, y: 4)
    }

    private func cardHeader(title: String, icon: String, iconColor: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(white: 0.6))
                .textCase(.uppercase)
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func progressBar(ratio: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * max(0.02, min(1.0, ratio)), height: 6)
            }
        }
        .frame(height: 6)
    }
}
