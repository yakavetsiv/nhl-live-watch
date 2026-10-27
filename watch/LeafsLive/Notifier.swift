import UserNotifications

/// Local notifications: event text you see on wrist raise, plus a reminder before puck drop.
enum Notifier {
    private static let reminderID = "game-reminder"

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Reminds you 10 minutes before the next game so you can open the app and start Live mode.
    static func scheduleReminder(for game: ScheduledGame) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        let fireDate = game.startTimeUTC.addingTimeInterval(-10 * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Leafs \(game.leafsAreHome ? "vs" : "at") \(game.opponent.abbrev) in 10 min"
        content.body = "Open Leafs Live and tap Go Live for goal taps."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger))
    }
}

/// Shows notifications as banners even while the app is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
