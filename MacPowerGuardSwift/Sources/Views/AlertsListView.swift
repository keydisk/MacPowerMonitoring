import SwiftUI

public struct AlertsListView: View {
    let alerts: [AlertItem]

    public init(alerts: [AlertItem]) {
        self.alerts = alerts
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("실시간 안전 진단 이벤트 & 알림")
                    .font(.headline)
                Spacer()
                Text("\(alerts.count)건")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if alerts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.title)
                        .foregroundStyle(.green)
                    Text("전원선 및 충전기 동작 상태 매우 양호함")
                        .font(.callout.weight(.medium))
                    Text("단절, 급격한 전압 강하, 과부하 등의 이상 징후가 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(alerts) { alert in
                            alertRow(alert)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }

    private func alertRow(_ alert: AlertItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: alert.level.symbol)
                .foregroundStyle(alert.level.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(alert.title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(Self.timeFormatter.string(from: alert.timestamp))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
}
