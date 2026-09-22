import SwiftUI

public struct DashboardView: View {
    @StateObject private var service = TelemetryService()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // 1. Header
                HeaderView(service: service)

                if !service.isConnected {
                    Label("이 Mac에서 배터리 전원 정보(AppleSmartBattery)를 읽을 수 없습니다. 배터리가 내장된 MacBook에서만 지원됩니다.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(RiskLevel.caution.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RiskLevel.caution.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // 2. 4 Top Metric Cards
                MetricCardView(service: service)

                // 3. 2 Realtime Waveform Charts (기존 웹 버전과 100% 동일)
                HStack(spacing: 16) {
                    WaveformChartView(
                        title: "실시간 소비 전력 (W) 파형",
                        icon: "📈",
                        points: service.powerHistory,
                        lineColor: Color(red: 0.02, green: 0.71, blue: 0.83), // #06b6d4
                        fillColorStart: Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.28),
                        fillColorEnd: Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.0),
                        unit: "W",
                        defaultMinY: 0.0,
                        defaultMaxY: 35.0
                    )

                    WaveformChartView(
                        title: "실시간 인입 전압 (V) 파형",
                        icon: "⚡",
                        points: service.voltageHistory,
                        lineColor: Color(red: 0.06, green: 0.73, blue: 0.51), // #10b981
                        fillColorStart: Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.25),
                        fillColorEnd: Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.0),
                        unit: "V",
                        defaultMinY: 18.0,
                        defaultMaxY: 21.0
                    )
                }

                // 4. Alerts Log & Hardware Specs
                HStack(alignment: .top, spacing: 16) {
                    AlertsListView(alerts: service.alertLog)
                    HardwareDetailsView(telemetry: service.telemetry)
                }
            }
            .padding(22)
        }
        .frame(minWidth: 1080, minHeight: 740)
        .background(
            ZStack {
                Color(red: 0.03, green: 0.05, blue: 0.08).ignoresSafeArea() // #080c14

                // Ambient Cyber Glow
                RadialGradient(
                    colors: [Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.06), Color.clear],
                    center: .topLeading,
                    startRadius: 50,
                    endRadius: 500
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.05), Color.clear],
                    center: .topTrailing,
                    startRadius: 50,
                    endRadius: 500
                )
                .ignoresSafeArea()
            }
        )
    }
}
