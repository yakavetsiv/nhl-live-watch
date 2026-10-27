import SwiftUI
import WidgetKit

@MainActor
final class GameTracker: ObservableObject {
    @Published private(set) var game: ScheduledGame?
    @Published private(set) var live: PlayByPlay?
    @Published private(set) var events: [GameEvent] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var error: String?
    /// Vertical page shown: 0 score, 1 events, 2 settings.
    @Published var page = 0

    let runner = BackgroundRunner()
    /// Set by the view from scenePhase. Notifications are only posted while the app is not on screen.
    var isActive = true

    private let client = NHLClient()
    private var detector = EventDetector()
    private var loop: Task<Void, Never>?
    /// Newest snapshot from the API. `live` lags it by the spoiler delay.
    private var latest: PlayByPlay?
    /// Fetched snapshots waiting out the spoiler delay, oldest first.
    private var buffer: [(fetched: Date, pbp: PlayByPlay)] = []

    /// Seconds to hold back score, events and haptics so they line up with a delayed stream.
    @AppStorage("spoilerDelay") var spoilerDelay = 0 {
        willSet { objectWillChange.send() }
        didSet { refreshNow() }
    }
    static let delayOptions = [0, 10, 20, 30, 45, 60, 90, 120, 180, 300]

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
        page = 0
        await Notifier.requestPermission()
        await runner.start()
        syncWidget()
        refreshNow()
    }

    /// Schedules the Go Live prompt for each upcoming game. Runs on launch and from background refresh.
    func refreshGamePrompts() async {
        guard let games = try? await client.upcomingGames(limit: Notifier.reminderLimit) else { return }
        await Notifier.scheduleGameStartPrompts(for: games)
    }

    func stopLive() {
        runner.stop()
        syncWidget()
    }

    /// One poll. Returns seconds until the next one.
    private func tick() async -> Double {
        do {
            if game == nil || !(game!.isLive) || latest.map({ GameState.isFinished($0.gameState) }) == true {
                let found = try await client.currentOrNextGame()
                if found?.id != game?.id { live = nil; latest = nil; buffer = []; detector.reset() }
                game = found
            }
            guard let game else { error = nil; return 1800 }

            let secondsToStart = game.startTimeUTC.timeIntervalSinceNow
            let gameWindow = game.isLive || (secondsToStart < 15 * 60 && !game.isFinished)
                || latest.map({ GameState.isLive($0.gameState) }) == true
            if gameWindow || latest == nil {
                let pbp = try await client.playByPlay(gameID: game.id)
                latest = pbp
                buffer.append((Date(), pbp))
                if GameState.isLive(pbp.gameState), !game.isLive {
                    self.game = try await client.currentOrNextGame() ?? game
                }
            }
            lastUpdate = Date()
            error = nil
        } catch {
            self.error = (error as? URLError)?.code == .notConnectedToInternet ? "Offline" : "Can't reach NHL"
            releaseDue()
            return min(15, secondsToNextRelease ?? 15)
        }

        releaseDue()
        if let pbp = live, GameState.isFinished(pbp.gameState), buffer.isEmpty {
            if runner.isRunning { runner.stop(); syncWidget() }
            return 600
        }
        let inGame = game?.isLive == true || latest.map({ GameState.isLive($0.gameState) }) == true
            || (game.map { $0.startTimeUTC.timeIntervalSinceNow < 15 * 60 && !$0.isFinished } ?? false)
        if inGame || !buffer.isEmpty {
            let interval: Double = runner.isRunning || isActive ? 8 : 30
            return min(interval, secondsToNextRelease ?? interval)
        }
        let secondsToStart = game?.startTimeUTC.timeIntervalSinceNow ?? 1800
        return min(max(secondsToStart - 10 * 60, 60), 1800)
    }

    /// Shows and announces every buffered snapshot that has waited out the spoiler delay.
    private func releaseDue() {
        let cutoff = Date().addingTimeInterval(-Double(spoilerDelay))
        var new: [GameEvent] = []
        while let first = buffer.first, first.fetched <= cutoff {
            buffer.removeFirst()
            live = first.pbp
            new += detector.ingest(first.pbp)
        }
        handle(new)
        syncWidget()
    }

    /// Shares the (delayed) game state with the Smart Stack widget and reloads it when something changed.
    func syncWidget() {
        guard let game else { return }
        let state = WidgetState(game: game, live: live, liveModeOn: runner.isRunning, spoilerDelay: spoilerDelay)
        var previous = WidgetState.load()
        previous?.updated = state.updated
        state.save()
        if previous != state { WidgetCenter.shared.reloadAllTimelines() }
    }

    private var secondsToNextRelease: Double? {
        buffer.first.map { max(1, $0.fetched.timeIntervalSinceNow + Double(spoilerDelay)) }
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
        Haptics.play(GameEvent(kind: kind, title: "", detail: "", won: true, periodEnd: true))
    }
}
