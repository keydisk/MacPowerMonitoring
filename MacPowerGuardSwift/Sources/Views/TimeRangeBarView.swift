import SwiftUI

// ==============================================================================
// 차트 시간 범위 선택 (세그먼트 피커 & 사용자 지정 DatePicker, LTTB 샘플링 상태 표시)
// ==============================================================================
public struct TimeRangeBarView: View {
    @ObservedObject var service: TelemetryService

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    public init(service: TelemetryService) {
        self.service = service
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Picker("표시 시간", selection: Binding(
                    get: { service.timeRangeOption },
                    set: { option in
                        DispatchQueue.main.async { service.selectTimeRange(option) }
                    }
                )) {
                    ForEach(TimeRangeOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Group {
                    Text("Mac 가동: \(service.macUptimeString)")
                    if service.isDownsampled {
                        Text("LTTB 샘플링 (원본 \(service.totalRawPoints)개 ➔ 300개 피크 보존)")
                    } else {
                        Text("1초 실시간 (\(service.currentDisplayCount)개)")
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            // 사용자 지정 모드: 최소 10분 ~ 최대 Mac 부팅 시각
            if service.timeRangeOption == .custom {
                HStack(spacing: 16) {
                    DatePicker(
                        "시작:",
                        selection: Binding(
                            get: { service.customStartDate },
                            set: { date in
                                DispatchQueue.main.async { service.customStartDate = date }
                            }
                        ),
                        in: min(service.macBootDate, service.customEndDate.addingTimeInterval(-600))...service.customEndDate.addingTimeInterval(-600),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .fixedSize()

                    DatePicker(
                        "종료:",
                        selection: Binding(
                            get: { service.customEndDate },
                            set: { date in
                                DispatchQueue.main.async { service.customEndDate = date }
                            }
                        ),
                        in: min(service.customStartDate.addingTimeInterval(600), Date())...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .fixedSize()

                    Button("현재로 맞춤") {
                        service.customEndDate = Date()
                    }

                    Spacer()

                    Text("최소 10분 ~ 최대 맥 부팅 시각(\(Self.dateFormatter.string(from: service.macBootDate)))까지 선택 가능")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .panel()
    }
}
