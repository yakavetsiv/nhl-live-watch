import UserNotifications

/// Local notifications: event text you see on wrist raise, plus a Go Live prompt at puck drop.
enum Notifier {
    static let gameStartCategory = "GAME_START"
    static let goLiveAction = "GO_LIVE"
    private static let reminderPrefix = "game-start-"
    /// watchOS keeps at most 64 pending notifications per app.
    static let reminderLimit = 20

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func registerCategories() {
        let goLive = UNNotificationAction(identifier: goLiveAction, title: "Go Live", options: [.foreground])
        let category = UNNotificationCategory(identifier: gameStartCategory, actions: [goLive], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Replaces the puck-drop prompts with one per upcoming game, so they fire even if the app
    /// has not been opened for days.
    static func scheduleGameStartPrompts(for games: [ScheduledGame]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        for game in games.prefix(reminderLimit) where game.startTimeUTC > Date() {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: game.startTimeUTC)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(
                identifier: reminderPrefix + String(game.id), content: gameStartContent(game), trigger: trigger))
        }
    }

    /// Sends the puck-drop prompt in a few seconds, to try the Go Live button.
    static func sendTestPrompt(for game: ScheduledGame?) {
        let content: UNMutableNotificationContent
        if let game {
            content = gameStartContent(game)
        } else {
            content = UNMutableNotificationContent()
            content.title = "Leafs game starting"
            content.body = "Tap Go Live for goal taps."
            content.categoryIdentifier = gameStartCategory
            content.sound = .default
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-prompt", content: content, trigger: trigger))
    }

    private static func gameStartContent(_ game: ScheduledGame) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Leafs \(game.leafsAreHome ? "vs" : "at") \(game.opponent.abbrev) is starting"
        content.body = "Tap Go Live for goal and penalty taps."
        content.categoryIdentifier = gameStartCategory
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        return content
    }
}

/// Shows notifications as banners even while the app is open, and handles the Go Live button.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    /// Set by the app to start Live mode.
    @MainActor var onGoLive: (() async -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let isGameStart = response.notification.request.content.categoryIdentifier == Notifier.gameStartCategory
        let tapped = response.actionIdentifier == Notifier.goLiveAction
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        guard isGameStart, tapped else { completionHandler(); return }
        Task { @MainActor in
            await self.onGoLive?()
            completionHandler()
        }
    }
}
