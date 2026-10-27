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
            // Goal horn: five strong taps.
            return [(.success, 0.45), (.notification, 0.45), (.success, 0.45), (.notification, 0.45), (.success, 0)]
        case .opponentGoal:
            return [(.failure, 0)]
        case .goalOverturned:
            return [(.retry, 0.6), (.retry, 0)]
        case .powerPlay:
            return [(.directionUp, 0.35), (.directionUp, 0)]
        case .leafsPenalty:
            return [(.directionDown, 0)]
        case .period:
            return [(.start, 0)]
        case .final:
            return event.won
                ? [(.success, 0.4), (.success, 0.4), (.notification, 0.4), (.success, 0.4), (.success, 0)]
                : [(.failure, 0.6), (.stop, 0)]
        }
    }

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
