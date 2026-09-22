import SwiftUI

// ==============================================================================
// 차트 시간 범위 선택 툴바 (DatePicker & LTTB 샘플링 상태 표시)
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
        VStack(spacing: 12) {
            // 1. 상단 프리셋 버튼 및 상태 바
            HStack(spacing: 10) {
                // 아이콘 및 라벨
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(Color(red: 0.02, green: 0.71, blue: 0.83))
                        .font(.system(size: 14, weight: .bold))
                    Text("표시 시간")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                // 프리셋 버튼 그룹
                HStack(spacing: 6) {
                    presetButton(.last10Min, label: "최근 10분 (기본)")
                    presetButton(.last30Min, label: "최근 30분")
                    presetButton(.last1Hour, label: "최근 1시간")
                    presetButton(.sinceBoot, label: "맥 실행 전체")
                    presetButton(.custom, label: "직접 선택 📅")
                }

                Spacer()

                // Mac 가동 시간 (Uptime) 뱃지
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 0.06, green: 0.73, blue: 0.51))
                        .frame(width: 6, height: 6)
                    Text("Mac 가동: \(service.macUptimeString)")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.75))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())

                // LTTB 샘플링 상태 뱃지
                HStack(spacing: 5) {
                    if service.isDownsampled {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                        Text("LTTB 샘플링 (원본 \(service.totalRawPoints)개 ➔ 300개 피크 보존)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                    } else {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundColor(Color(red: 0.06, green: 0.73, blue: 0.51))
                        Text("1초 실시간 (\(service.currentDisplayCount)개)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.7))
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(service.isDownsampled ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.12) : Color.white.opacity(0.04))
                .clipShape(Capsule())
            }

            // 2. 사용자 지정(DatePicker) 모드일 때 나타나는 상세 설정 패널
            if service.timeRangeOption == .custom {
                HStack(spacing: 16) {
                    // 시작 일시 피커
                    HStack(spacing: 8) {
                        Text("시작:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(white: 0.7))

                        DatePicker(
                            "",
                            selection: $service.customStartDate,
                            in: service.macBootDate...service.customEndDate.addingTimeInterval(-600),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.4))

                    // 종료 일시 피커
                    HStack(spacing: 8) {
                        Text("종료:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(white: 0.7))

                        DatePicker(
                            "",
                            selection: $service.customEndDate,
                            in: service.customStartDate.addingTimeInterval(600)...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }

                    // 현재 시각으로 맞춤 버튼
                    Button(action: {
                        service.customEndDate = Date()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text("현재로 맞춤")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // 가이드 안내 (최소 10분, 최대 맥 부팅 시각)
                    Text("💡 최소 10분 ~ 최대 맥 부팅 시각(\(Self.dateFormatter.string(from: service.macBootDate)))까지 선택 가능")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(Color(red: 0.06, green: 0.09, blue: 0.14).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func presetButton(_ option: TimeRangeOption, label: String) -> some View {
        let isSelected = service.timeRangeOption == option
        Button(action: {
            service.selectTimeRange(option)
        }) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : Color(white: 0.7))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    isSelected
                        ? Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.3)
                        : Color.white.opacity(0.04)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color(red: 0.02, green: 0.71, blue: 0.83) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
