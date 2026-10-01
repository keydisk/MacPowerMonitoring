import Foundation

// 실제 장치 읽기 확인: 단위와 수치만 출력하며 기기 식별자는 출력하지 않는다.
@main
struct LiveTelemetryCheck {
    @MainActor static func main() async {
        let service = TelemetryService()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        service.stop()
        print("CPU %:", service.cpuUsagePct as Any)
        print("GPU %:", service.gpuUsagePct as Any)
        print("Supply W:", service.telemetry?.suppliedPowerW as Any)
        print("System W:", service.telemetry?.systemLoadW as Any)
        print("Battery W:", service.telemetry?.batteryPowerW as Any)
        print("Battery °C:", service.telemetry?.batteryTemperatureC as Any)
        print("Cell group V:", service.telemetry?.cellVoltagesV as Any)
    }
}
