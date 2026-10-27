import WatchKit

/// Each event kind gets its own rhythm so you can tell what happened without looking.
@MainActor
enum Haptics {
    private static var playing: Task<Void, Never>?

    static func play(_ event: GameEvent) {
        play(pattern(for: event))
    }

    static func pattern(for event: GameEvent) -> [(WKHapticType, Double)] {
        switch event.kind {
        case .leafsGoal:
            // Three strong taps.
            return [(.notification, 0.35), (.notification, 0.35), (.notification, 0)]
        case .opponentGoal:
            return [(.failure, 0)]
        case .goalOverturned:
            return [(.retry, 0.6), (.retry, 0)]
        case .powerPlay:
            // Four even taps.
            return [(.click, 0.3), (.click, 0.3), (.click, 0.3), (.click, 0)]
        case .leafsPenalty:
            // Followed team short-handed: one quick double tap.
            return [(.directionDown, 0.18), (.directionDown, 0)]
        case .period:
            return event.periodEnd ? twoThenOne : [(.start, 0)]
        case .final:
            return twoThenOne
        }
    }

    /// Two quick taps, a pause, one tap: end of a period and the final horn.
    private static let twoThenOne: [(WKHapticType, Double)] = [(.notification, 0.2), (.notification, 0.8), (.notification, 0)]

    private static func play(_ steps: [(WKHapticType, Double)]) {
        playing?.cancel()
        playing = Task { @MainActor in
            for (type, pause) in steps {
                if Task.isCancelled { return }
                WKInterfaceDevice.current().play(type)
                if pause > 0 { try? await Task.sleep(for: .seconds(pause)) }
            }
        }
    }
}
