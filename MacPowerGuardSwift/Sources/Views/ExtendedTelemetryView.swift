import SwiftUI

struct ExtendedTelemetryView: View {
    @ObservedObject var service: TelemetryService

    var body: some View {
        let t = service.telemetry
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("전력 흐름", systemImage: "bolt.horizontal.circle")
                        .font(.headline)
                    Text(t?.systemLoadW.map { String(format: "%.1f W", $0) } ?? "-- W")
                        .font(.system(size: 28, weight: .semibold)).monospacedDigit().foregroundStyle(.blue)
                    value("공급 전력", format(t?.suppliedPowerW, "W"))
                    value("시스템 소비 전력", format(t?.systemLoadW, "W"))
                    value("배터리 충전 / 방전", t?.batteryPowerW.map { String(format: "%+.2f W", $0) } ?? "-- W")
                    value("USB 출력 전력", format(t?.usbOutputPowerW, "W"))
                    Text("배터리 +는 충전, −는 방전입니다. 전력은 팩 전압 × 전류로 계산합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).panel()

                VStack(alignment: .leading, spacing: 10) {
                    Label("배터리 정밀 정보", systemImage: "battery.100")
                        .font(.headline)
                    Text(t?.batteryPowerW.map { String(format: "%+.2f W", $0) } ?? "-- W")
                        .font(.system(size: 28, weight: .semibold)).monospacedDigit().foregroundStyle(.purple)
                    value("배터리 성능", t?.batteryHealthPct.map { "\($0)%" } ?? "--")
                    value("설계 / 완충 용량", "\(format(t?.designCapacityMah, "mAh")) / \(format(t?.fullCapacityMah, "mAh"))")
                    value("배터리 팩 전압", format(t?.batteryVoltageV, "V"))
                    value("배터리 팩 온도", format(t?.batteryTemperatureC, "°C"))
                    value("셀 그룹 전압", t?.cellVoltagesV.isEmpty == false ? t!.cellVoltagesV.map { String(format: "%.3f V", $0) }.joined(separator: " · ") : "-- V")
                }
                .frame(maxWidth: .infinity, alignment: .leading).panel()

                VStack(alignment: .leading, spacing: 10) {
                    Label("시스템 상태", systemImage: "cpu")
                        .font(.headline)
                    Text(service.cpuUsagePct.map { String(format: "%.0f%%", $0) } ?? "--%")
                        .font(.system(size: 28, weight: .semibold)).monospacedDigit().foregroundStyle(.orange)
                    ProgressView(value: service.cpuUsagePct ?? 0, total: 100).tint(.orange)
                    value("CPU 사용량", format(service.cpuUsagePct, "%"))
                    value("GPU 사용량", format(service.gpuUsagePct, "%"))
                    value("GPU Renderer / Tiler", "\(format(service.gpuRendererPct, "%")) / \(format(service.gpuTilerPct, "%"))")
                    value("열 압력", thermalTitle(service.thermalState))
                    value("열로 인한 충전 제한", t.map { "\($0.thermalLimitedSec) s" } ?? "-- s")
                    value("측정 오류", t.map { "\($0.telemetryErrors)" } ?? "--")
                    Text("CPU 사용량은 전체 코어를 0~100%로 정규화합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).panel()
            }
            DisclosureGroup("SoC · 센서 접근 상태") {
                VStack(alignment: .leading, spacing: 8) {
                    value("CPU E / P · GPU · ANE · DRAM · SoC", String(localized: "현재 배포에서 접근 불가"))
                    value("디스플레이 · CPU/GPU 온도 · 팬 RPM", String(localized: "현재 배포에서 접근 불가"))
                    value("충전 컨트롤러 온도", String(localized: "현재 배포에서 접근 불가"))
                    Text("SoC 세부 전력은 IOReport 또는 관리자 권한의 powermetrics가 필요하며, SMC 센서는 기기별 비공개 인터페이스를 사용합니다. 현재 앱은 이 데이터를 수집하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }.panel()
        }
    }

    private func value(_ name: LocalizedStringKey, _ reading: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(reading).monospacedDigit().textSelection(.enabled)
        }.font(.callout)
    }

    private func format(_ number: Double?, _ unit: String) -> String {
        number.map { String(format: "%.2f %@", $0, unit) } ?? "-- \(unit)"
    }
}

func thermalTitle(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "Nominal"
    case .fair: return "Fair"
    case .serious: return "Serious"
    case .critical: return "Critical"
    @unknown default: return "--"
    }
}
