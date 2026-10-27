import SwiftUI
import UserNotifications
import WatchKit

@main
struct PuckPulseApp: App {
    @StateObject private var tracker = GameTracker()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        Notifier.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(tracker.runner)
                .onOpenURL { url in
                    if url.host == "golive" { Task { await tracker.goLive() } }
                }
                .task {
                    NotificationPresenter.shared.onGoLive = { [tracker] in await tracker.goLive() }
                    await Notifier.requestPermission()
                    await tracker.refreshGamePrompts()
                    Self.scheduleScheduleRefresh()
                }
        }
        .backgroundTask(.appRefresh) { _ in
            // Keeps puck-drop prompts current when the app isn't opened for a while.
            await tracker.refreshGamePrompts()
            await MainActor.run { Self.scheduleScheduleRefresh() }
        }
    }

    @MainActor
    private static func scheduleScheduleRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(12 * 3600), userInfo: nil) { _ in }
    }
}

extension Color {
    static let rink = Color(red: 0, green: 32 / 255, blue: 91 / 255)
    static let rinkBright = Color(red: 0.18, green: 0.42, blue: 0.95)
}
