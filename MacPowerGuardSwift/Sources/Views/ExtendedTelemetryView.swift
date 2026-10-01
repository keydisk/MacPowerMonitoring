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
                    Text("배터리 +는 충전, −는 방전입니다. 전력은 팩 전압 × 전류로 계산합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("상세 정보").font(.caption).foregroundStyle(.secondary)
                    value("USB 포트 출력 (연결된 외부 장치로 나가는 전력)", format(t?.usbOutputPowerW, "W"))
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
                    value("System Thermal State", thermalTitle(service.thermalState), tableName: "Thermal")
                    value("열로 인한 충전 제한", t.map { "\($0.thermalLimitedSec) s" } ?? "-- s")
                    value("측정 오류", t.map { "\($0.telemetryErrors)" } ?? "--")
                    Text("시스템의 PowerTelemetryErrorCount 값 (Mac 부팅 이후 누적)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("CPU 사용량은 전체 코어를 0~100%로 정규화합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).panel()
            }
        }
    }

    private func value(_ name: LocalizedStringKey, _ reading: String, tableName: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name, tableName: tableName).foregroundStyle(.secondary)
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
    case .nominal: return String(localized: "Normal", table: "Thermal")
    case .fair: return String(localized: "Slightly Elevated", table: "Thermal")
    case .serious: return String(localized: "High", table: "Thermal")
    case .critical: return String(localized: "Very High", table: "Thermal")
    @unknown default: return "--"
    }
}
