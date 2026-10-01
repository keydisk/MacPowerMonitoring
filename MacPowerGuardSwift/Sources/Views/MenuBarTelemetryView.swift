import SwiftUI
import AppKit

struct MenuBarPreferencesView: View {
    @AppStorage("menuShowPower") private var showPower = true
    @AppStorage("menuShowCPU") private var showCPU = true
    @AppStorage("menuShowGPU") private var showGPU = true
    var body: some View {
        Toggle("소비 전력 표시", isOn: $showPower)
        Toggle("CPU 사용량 표시", isOn: $showCPU)
        Toggle("GPU 사용량 표시", isOn: $showGPU)
    }
}

struct MenuBarTelemetryLabel: View {
    @ObservedObject var service: TelemetryService
    @AppStorage("menuShowPower") private var showPower = true
    @AppStorage("menuShowCPU") private var showCPU = true
    @AppStorage("menuShowGPU") private var showGPU = true

    var body: some View {
        HStack(spacing: 6) {
            if showPower {
                Image(systemName: "bolt.fill")
                Text(service.telemetry?.systemLoadW.map { String(format: "%.1f W", $0) } ?? "-- W")
            }
            if showCPU {
                Text(service.cpuUsagePct.map { String(format: "CPU %.0f%%", $0) } ?? "CPU --%")
            }
            if showGPU {
                Text(service.gpuUsagePct.map { String(format: "GPU %.0f%%", $0) } ?? "GPU --%")
            }
            if !showPower && !showCPU && !showGPU { Image(systemName: "bolt.circle") }
        }.monospacedDigit()
    }
}

struct MenuBarTelemetryView: View {
    @ObservedObject var service: TelemetryService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mac Telemetry").font(.headline)
            Label(service.isPaused ? LocalizedStringKey("일시정지됨") : "실시간 모니터링", systemImage: service.isPaused ? "pause.circle" : "waveform.path")
            Text("공급 전력: \(service.telemetry?.suppliedPowerW.map { String(format: "%.1f W", $0) } ?? "-- W")")
            Text(String(localized: "System Thermal State", table: "Thermal") + ": " + thermalTitle(service.thermalState))
            Text("GPU: \(service.gpuUsagePct.map { String(format: "%.0f%%", $0) } ?? "--%")")
            Divider()
            MenuBarPreferencesView()
            Divider()
            Button("대시보드 열기") {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(service.isPaused ? LocalizedStringKey("모니터링 재개") : "일시정지") { service.togglePause() }
            Button("종료") { NSApp.terminate(nil) }
        }
        .padding(16).frame(width: 300)
    }
}
