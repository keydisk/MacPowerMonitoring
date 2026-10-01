import SwiftUI

@main
public struct MacPowerGuardApp: App {
    @StateObject private var service = TelemetryService()
    @AppStorage("showMenuBar") private var showMenuBar = true
    public init() {}

    public var body: some Scene {
        WindowGroup("Mac Telemetry", id: "dashboard") {
            DashboardView(service: service)
        }
        .defaultSize(width: 1180, height: 820)
        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarTelemetryView(service: service)
        } label: {
            MenuBarTelemetryLabel(service: service)
        }
        .menuBarExtraStyle(.window)
        Settings {
            Form {
                Toggle("메뉴 막대에 표시", isOn: $showMenuBar)
                MenuBarPreferencesView()
            }
            .padding(24)
            .frame(width: 360)
        }
    }
}
