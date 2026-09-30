import SwiftUI

public struct DashboardView: View {
    @StateObject private var service = TelemetryService()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !service.isConnected {
                    Label("이 Mac에서 배터리 전원 정보(AppleSmartBattery)를 읽을 수 없습니다. 배터리가 내장된 MacBook에서만 지원됩니다.", systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()
                }

                MetricCardView(service: service)

                TimeRangeBarView(service: service)

                HStack(spacing: 16) {
                    WaveformChartView(
                        title: "실시간 소비 전력 (W) 파형",
                        points: service.powerHistory,
                        lineColor: .blue,
                        unit: "W",
                        defaultMinY: 0.0,
                        defaultMaxY: 35.0,
                        timeSpanText: service.timeSpanDescription,
                        suppliedPowerW: service.telemetry.flatMap { $0.isInputMeasured ? $0.systemPowerW : nil }
                    )

                    WaveformChartView(
                        title: "실시간 인입 전압 (V) 파형",
                        points: service.voltageHistory,
                        lineColor: .green,
                        unit: "V",
                        defaultMinY: 18.0,
                        defaultMaxY: 21.0,
                        thresholdValue: (service.telemetry?.externalConnected == true ? (service.telemetry?.adapterVoltageV ?? 20.0) : nil),
                        timeSpanText: service.timeSpanDescription
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    AlertsListView(alerts: service.alertLog)
                    HardwareDetailsView(telemetry: service.telemetry)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(minWidth: 1080, minHeight: 740)
        .toolbar {
            // 상태 문구는 버튼과 별도 항목으로 두고 좌우 여백을 줘서 툴바 배경 가장자리에 붙지 않게 함
            ToolbarItem {
                (service.isPaused ? Text("일시정지됨") : Text("실시간 수신 (\(service.packetCount)회 · 1초 주기)"))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }

            ToolbarItemGroup {
                Button { service.toggleSound() } label: {
                    Label(service.soundEnabled ? LocalizedStringKey("경고음 켜짐") : "경고음 켜기",
                          systemImage: service.soundEnabled ? "bell.fill" : "bell.slash")
                }
                .help(service.soundEnabled ? LocalizedStringKey("경고음 켜짐") : "경고음 켜기")

                Button { service.togglePause() } label: {
                    Label(service.isPaused ? LocalizedStringKey("모니터링 재개") : "일시정지",
                          systemImage: service.isPaused ? "play.fill" : "pause.fill")
                }
                .help(service.isPaused ? LocalizedStringKey("모니터링 재개") : "일시정지")
            }
        }
    }
}

extension View {
    /// 대시보드 공통 패널: 시스템 배경색 + 얇은 구분선 테두리 (라이트/다크 모드 자동 대응)
    func panel() -> some View {
        padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
