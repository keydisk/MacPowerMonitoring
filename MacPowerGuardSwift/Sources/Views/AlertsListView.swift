import SwiftUI

public struct AlertsListView: View {
    let alerts: [AlertItem]
    let isScrollable: Bool

    public init(alerts: [AlertItem], isScrollable: Bool = true) {
        self.alerts = alerts
        self.isScrollable = isScrollable
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("실시간 안전 진단 이벤트 & 알림")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(alerts.count)건")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .foregroundColor(Color(white: 0.6))
            }

            if alerts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 30))
                        .foregroundColor(Color(red: 0.06, green: 0.73, blue: 0.51))
                    Text("전원선 및 충전기 동작 상태 매우 양호함")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("단절, 급격한 전압 강하, 과부하 등의 이상 징후가 없습니다.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(white: 0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 28)
            } else if isScrollable {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(alerts) { alert in
                            alertRow(alert)
                        }
                    }
                }
                .frame(maxHeight: 220)
            } else {
                VStack(spacing: 10) {
                    ForEach(alerts) { alert in
                        alertRow(alert)
                    }
                }
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

    private func alertRow(_ alert: AlertItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(alert.level.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(Self.timeFormatter.string(from: alert.timestamp))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.45))
                }

                Text(alert.message)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(white: 0.7))
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(alert.level.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

