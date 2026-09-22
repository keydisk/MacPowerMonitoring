import SwiftUI

@main
public struct MacPowerGuardApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1180, height: 820)
    }
}
