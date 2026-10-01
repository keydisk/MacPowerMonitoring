import SwiftUI

public struct HardwareDetailsView: View {
    let telemetry: PowerTelemetry?

    public init(telemetry: PowerTelemetry?) {
        self.telemetry = telemetry
    }

    public var body: some View {
        let t = telemetry

        VStack(alignment: .leading, spacing: 10) {
            Text("하드웨어 & 전원 스펙 텔레메트리")
                .font(.headline)

            VStack(spacing: 0) {
                row(label: "전원 공급 상태", value: t?.externalConnected == true ? String(localized: "AC 어댑터 전원 연결됨") : String(localized: "내장 배터리 전원 구동 중"))
                row(label: "어댑터 정격 규격", value: t?.adapterWatts.map { "\(Int($0))W (\(t!.adapterDesc))" } ?? String(localized: "연결 없음"))
                row(label: "공급 전력", value: t?.suppliedPowerW.map { String(format: "%.1f W", $0) } ?? "-- W")
                if let t, t.isInputMeasured, let aV = t.adapterVoltageV {
                    row(label: "정격 / 인입 전압", value: String(format: "%.2f V / %.2f V", aV, t.systemVoltageV))
                } else {
                    row(label: "배터리 팩 전압", value: t.map { String(format: "%.2f V", $0.systemVoltageV) } ?? "-")
                }
                row(label: "정격 대비 전압 강하율", value: t?.voltageDropPct.map { String(format: "%.2f%%", $0) } ?? "-")
                if t?.voltageDropPct != nil {
                    Text("앱 내부 참고 임계값: 4.5% / 7.0%.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                row(label: "배터리 충전 상태", value: t.map { "\($0.batteryLevelPct.map { "\($0)%" } ?? "--") · \($0.chargeStateText)" } ?? "-")
                row(label: "배터리 최대 용량 & 사이클", value: String(localized: "\(t?.batteryHealthPct.map { "\($0)%" } ?? "--") (사이클: \(t?.batteryCycleCount.map(String.init) ?? "--")회)"))
            }
            DisclosureGroup("고급 정보") {
                row(label: "하드웨어 Family Code", value: t?.familyCode ?? "-", divider: false)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }

    private func row(label: LocalizedStringKey, value: String, divider: Bool = true) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if divider { Divider() }
        }
    }
}
