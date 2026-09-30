import Foundation
import Combine

// swiftc로 앱 모델 소스와 함께 실행하는 시간 범위 회귀 검사.
@main
struct TelemetryRangeCheck {
    @MainActor static func main() async {
        let service = TelemetryService()
        service.stop()
        service.selectTimeRange(.custom)
        var publications = 0
        let subscription = service.objectWillChange.sink { publications += 1 }

        service.customStartDate = Date().addingTimeInterval(3600)
        service.customEndDate = Date().addingTimeInterval(-3600)
        // 입력값 2개 외에는 같은 호출 스택에서 게시하지 않아야 한다.
        assert(publications == 2)
        try? await Task.sleep(nanoseconds: 50_000_000)
        assert(service.customEndDate.timeIntervalSince(service.customStartDate) >= 600)
        assert(service.customEndDate <= Date())

        service.customEndDate = Date().addingTimeInterval(86400)
        try? await Task.sleep(nanoseconds: 50_000_000)
        assert(service.customEndDate <= Date())
        let settledCount = publications
        try? await Task.sleep(nanoseconds: 50_000_000)
        assert(publications == settledCount, "날짜 보정이 계속 재게시됨")
        withExtendedLifetime(subscription) {}
        print("TelemetryRangeCheck passed")
    }
}
