import SwiftUI
import UserNotifications

@main
struct LeafsLiveApp: App {
    @StateObject private var tracker = GameTracker()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(tracker.runner)
        }
    }
}

extension Color {
    static let leafsBlue = Color(red: 0, green: 32 / 255, blue: 91 / 255)
    static let leafsBright = Color(red: 0.18, green: 0.42, blue: 0.95)
}
