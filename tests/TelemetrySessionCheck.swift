import Foundation

@main
struct TelemetrySessionCheck {
    @MainActor static func main() {
        let service = TelemetryService()
        service.stop()
        service.updateDisplayHistories()
        assert(service.totalRawPoints == 0)
        assert(service.currentDisplayCount == 0)
        assert(!service.isDownsampled)

        // 24시간을 넘긴 전체 실행 기록도 첫 샘플과 마지막 샘플을 유지한다.
        let start = Date(timeIntervalSince1970: 0)
        let points = (0..<90_000).map {
            ChartPoint(time: start.addingTimeInterval(Double($0)), value: Double($0 % 100))
        }
        let displayed = LTTBDownsampler.downsample(points, targetCount: 300)
        assert(displayed.count == 300)
        assert(displayed.first?.id == points.first?.id)
        assert(displayed.last?.id == points.last?.id)
        print("TelemetrySessionCheck passed")
    }
}
