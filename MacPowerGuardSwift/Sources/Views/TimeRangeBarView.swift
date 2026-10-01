import SwiftUI

// 앱 실행 전체 표시 범위와 샘플링 상태 (기간 선택 옵션 없음).
public struct TimeRangeBarView: View {
    @ObservedObject var service: TelemetryService

    public init(service: TelemetryService) {
        self.service = service
    }

    public var body: some View {
        HStack(spacing: 16) {
            Text(service.timeSpanDescription)
            Spacer()
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
        .panel()
    }
}
