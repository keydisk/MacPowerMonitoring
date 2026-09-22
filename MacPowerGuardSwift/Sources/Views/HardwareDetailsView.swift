import SwiftUI

public struct HardwareDetailsView: View {
    let telemetry: PowerTelemetry?

    public init(telemetry: PowerTelemetry?) {
        self.telemetry = telemetry
    }

    public var body: some View {
        let t = telemetry

        VStack(alignment: .leading, spacing: 14) {
            Text("하드웨어 & 전원 스펙 텔레메트리")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 8) {
                row(label: "전원 공급 상태", value: t?.externalConnected == true ? "AC 어댑터 전원 연결됨" : "내장 배터리 전원 구동 중")
                row(label: "어댑터 정격 규격", value: t?.adapterWatts != nil ? "\(Int(t!.adapterWatts!))W (\(t!.adapterDesc))" : "연결 없음")
                row(label: "정격 / 인입 전압", value: String(format: "%.2f V / %.2f V", (t?.adapterVoltageV ?? 0.0), (t?.systemVoltageV ?? 0.0)))
                row(label: "정격 대비 전압 강하율", value: t?.voltageDropPct != nil ? String(format: "%.2f%% (정상 범위)", t!.voltageDropPct!) : "-")
                row(label: "배터리 충전 상태", value: t?.isCharging == true ? "충전 중 (Charging)" : (t?.externalConnected == true ? "완충 / 전원 유지" : "방전 중"))
                row(label: "배터리 수명 & 사이클", value: "\(t?.batteryLevelPct ?? 0)% (사이클: \(t?.batteryCycleCount ?? 0)회)")
                row(label: "하드웨어 Family Code", value: t?.familyCode ?? "-")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.85)) // #0f172a
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 4)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundColor(Color(white: 0.55))
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
