import SwiftUI

@MainActor
final class GameTracker: ObservableObject {
    @Published private(set) var game: ScheduledGame?
    @Published private(set) var live: PlayByPlay?
    @Published private(set) var events: [GameEvent] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var error: String?

    let runner = BackgroundRunner()
    /// Set by the view from scenePhase. Notifications are only posted while the app is not on screen.
    var isActive = true

    private let client = NHLClient()
    private var detector = EventDetector()
    private var loop: Task<Void, Never>?

    @AppStorage("disabledKinds") private var disabledKindsRaw = ""

    func isEnabled(_ kind: EventKind) -> Bool { !disabledKindsRaw.split(separator: ",").contains(Substring(kind.rawValue)) }

    func setEnabled(_ kind: EventKind, _ on: Bool) {
        var set = Set(disabledKindsRaw.split(separator: ",").map(String.init))
        if on { set.remove(kind.rawValue) } else { set.insert(kind.rawValue) }
        disabledKindsRaw = set.sorted().joined(separator: ",")
        objectWillChange.send()
    }

    func startPolling() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let delay = await self?.tick() ?? 60
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func refreshNow() {
        loop?.cancel()
        loop = nil
        startPolling()
    }

    func goLive() async {
        await Notifier.requestPermission()
        await runner.start()
        refreshNow()
    }

    func stopLive() {
        runner.stop()
    }

    /// One poll. Returns seconds until the next one.
    private func tick() async -> Double {
        do {
            if game == nil || !(game!.isLive) || live.map({ GameState.isFinished($0.gameState) }) == true {
                let found = try await client.currentOrNextGame()
                if found?.id != game?.id { live = nil; detector.reset() }
                game = found
                if let found, !found.isLive, !found.isFinished { Notifier.scheduleReminder(for: found) }
            }
            guard let game else { error = nil; return 1800 }

            let secondsToStart = game.startTimeUTC.timeIntervalSinceNow
            let gameWindow = game.isLive || (secondsToStart < 15 * 60 && !game.isFinished)
            if gameWindow || live == nil {
                let pbp = try await client.playByPlay(gameID: game.id)
                live = pbp
                handle(detector.ingest(pbp))
                if GameState.isLive(pbp.gameState), !game.isLive {
                    self.game = try await client.currentOrNextGame() ?? game
                }
            }
            lastUpdate = Date()
            error = nil

            if let pbp = live, GameState.isFinished(pbp.gameState) {
                if runner.isRunning { runner.stop() }
                return 600
            }
            if gameWindow { return runner.isRunning || isActive ? 8 : 30 }
            return min(max(secondsToStart - 10 * 60, 60), 1800)
        } catch {
            self.error = (error as? URLError)?.code == .notConnectedToInternet ? "Offline" : "Can't reach NHL"
            return 15
        }
    }

    private func handle(_ new: [GameEvent]) {
        guard !new.isEmpty else { return }
        events.insert(contentsOf: new.reversed(), at: 0)
        if events.count > 30 { events.removeLast(events.count - 30) }

        let wanted = new.filter { isEnabled($0.kind) }
        if let top = wanted.min(by: { $0.kind.priority < $1.kind.priority }) {
            Haptics.play(top)
        }
        if !isActive, !wanted.isEmpty {
            let lead = wanted.min(by: { $0.kind.priority < $1.kind.priority })!
            let body = wanted.map { $0.kind == lead.kind && wanted.count == 1 ? $0.detail : "\($0.title): \($0.detail)" }
                .joined(separator: "\n")
            Notifier.post(title: lead.title, body: body)
        }
    }

    /// Plays one sample of each pattern from Settings.
    func preview(_ kind: EventKind) {
        Haptics.play(GameEvent(kind: kind, title: "", detail: "", won: true))
    }
}
