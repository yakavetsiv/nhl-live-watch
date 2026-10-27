import SwiftUI
import WidgetKit

/// One game being followed, seen from the side of `team`.
@MainActor
final class GameSlot: Identifiable {
    let team: String
    var game: ScheduledGame
    /// Snapshot on screen. Lags `latest` by the spoiler delay.
    var live: PlayByPlay?
    /// Newest snapshot from the API.
    var latest: PlayByPlay?
    /// Fetched snapshots waiting out the spoiler delay, oldest first.
    var buffer: [(fetched: Date, pbp: PlayByPlay)] = []
    var detector = EventDetector()

    var id: Int { game.id }

    init(team: String, game: ScheduledGame) {
        self.team = team
        self.game = game
    }

    private var latestFinished: Bool { latest.map { GameState.isFinished($0.gameState) } ?? false }

    var isLiveNow: Bool { game.isLive || latest.map { GameState.isLive($0.gameState) } == true }

    /// Live, or close enough to puck drop to poll every few seconds.
    var inWindow: Bool {
        !latestFinished && (isLiveNow || (game.startTimeUTC.timeIntervalSinceNow < 15 * 60 && !game.isFinished))
    }

    /// Over, and the spoiler delay has caught up with the final horn.
    var isDone: Bool { live.map { GameState.isFinished($0.gameState) } == true && buffer.isEmpty }

    func widgetState(liveModeOn: Bool, spoilerDelay: Int) -> WidgetState {
        WidgetState(team: team, game: game, live: live, liveModeOn: liveModeOn, spoilerDelay: spoilerDelay)
    }
}

@MainActor
final class GameTracker: ObservableObject {
    @Published private(set) var teams: [Team] = GameTracker.initialTeams()

    private static func initialTeams() -> [Team] {
        #if DEBUG
        // Simulator screenshots: launching with `-seedTeams TOR,EDM` skips the team picker.
        if let seed = UserDefaults.standard.string(forKey: "seedTeams") {
            let teams = seed.split(separator: ",").map { Team(league: .nhl, abbrev: String($0), name: String($0)) }
            FollowedTeams.save(teams)
            return teams
        }
        #endif
        return FollowedTeams.load()
    }
    /// One slot per followed game: live first, then upcoming by start time, then finished.
    @Published private(set) var slots: [GameSlot] = []
    @Published private(set) var events: [GameEvent] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var error: String?
    /// Vertical page shown: game pages are 0..<slots.count, then the events and settings pages.
    @Published var page = 0
    static let eventsPage = 100
    static let settingsPage = 101

    let runner = BackgroundRunner()
    /// Set by the view from scenePhase. Notifications are only posted while the app is not on screen.
    var isActive = true

    private let client = NHLClient()
    private var loop: Task<Void, Never>?

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

    func setTeams(_ new: [Team]) {
        FollowedTeams.save(new)
        teams = new
        slots = []
        page = 0
        refreshNow()
        Task { await refreshGamePrompts() }
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

    func stopLive() {
        runner.stop()
        syncWidget()
    }

    /// Schedules the Go Live prompt for the next games of all followed teams. Runs on launch and from
    /// background refresh.
    func refreshGamePrompts() async {
        var seen = Set<Int>()
        var all: [(game: ScheduledGame, team: String)] = []
        for team in FollowedTeams.nhlAbbrevs {
            guard let games = try? await client.upcomingGames(team: team) else { continue }
            for game in games where seen.insert(game.id).inserted { all.append((game, team)) }
        }
        all.sort { $0.game.startTimeUTC < $1.game.startTimeUTC }
        await Notifier.scheduleGameStartPrompts(for: Array(all.prefix(Notifier.reminderLimit)))
    }

    /// One poll. Returns seconds until the next one.
    private func tick() async -> Double {
        let abbrevs = teams.filter { $0.league == .nhl }.map(\.abbrev)
        guard !abbrevs.isEmpty else { slots = []; return 1800 }

        var failed = false
        // Find each team's current or next game. A game between two followed teams appears once.
        var next: [GameSlot] = []
        for team in abbrevs {
            let existing = slots.first { $0.team == team }
            var game = existing?.game
            if existing == nil || existing?.inWindow == false {
                do { game = try await client.currentOrNextGame(team: team) } catch { failed = true }
            }
            guard let game, !next.contains(where: { $0.id == game.id }) else { continue }
            let slot = slots.first { $0.id == game.id } ?? GameSlot(team: team, game: game)
            slot.game = game
            next.append(slot)
        }

        for slot in next where slot.inWindow || slot.latest == nil {
            do {
                let pbp = try await client.playByPlay(gameID: slot.id)
                slot.latest = pbp
                slot.buffer.append((Date(), pbp))
                if GameState.isLive(pbp.gameState), !slot.game.isLive,
                   let fresh = try await client.currentOrNextGame(team: slot.team), fresh.id == slot.id {
                    slot.game = fresh
                }
            } catch { failed = true }
        }

        slots = next.sorted {
            $0.widgetState(liveModeOn: false, spoilerDelay: 0).displayRank
                < $1.widgetState(liveModeOn: false, spoilerDelay: 0).displayRank
        }
        error = failed ? "Can't reach NHL" : nil
        if !failed { lastUpdate = Date() }
        releaseDue()

        let active = slots.contains { $0.inWindow || !$0.buffer.isEmpty }
        if runner.isRunning, !active, slots.contains(where: \.isDone) {
            runner.stop()
            syncWidget()
        }
        if failed { return min(15, secondsToNextRelease ?? 15) }
        if active {
            let interval: Double = runner.isRunning || isActive ? 8 : 30
            return min(interval, secondsToNextRelease ?? interval)
        }
        let soonest = slots.map { $0.game.startTimeUTC.timeIntervalSinceNow }.filter { $0 > 0 }.min() ?? 1800
        return min(max(soonest - 10 * 60, 60), 1800)
    }

    /// Shows and announces every buffered snapshot that has waited out the spoiler delay.
    private func releaseDue() {
        let cutoff = Date().addingTimeInterval(-Double(spoilerDelay))
        var new: [GameEvent] = []
        for slot in slots {
            while let first = slot.buffer.first, first.fetched <= cutoff {
                slot.buffer.removeFirst()
                slot.live = first.pbp
                new += slot.detector.ingest(first.pbp, us: slot.team)
            }
        }
        objectWillChange.send()
        handle(new)
        syncWidget()
    }

    /// Shares the most relevant game with the Smart Stack widget and reloads it when something changed.
    func syncWidget() {
        let states = slots.map { $0.widgetState(liveModeOn: runner.isRunning, spoilerDelay: spoilerDelay) }
        guard let state = states.min(by: { $0.displayRank < $1.displayRank }) else { return }
        var previous = WidgetState.load()
        previous?.updated = state.updated
        state.save()
        if previous != state { WidgetCenter.shared.reloadAllTimelines() }
    }

    private var secondsToNextRelease: Double? {
        slots.compactMap { $0.buffer.first?.fetched }.min()
            .map { max(1, $0.timeIntervalSinceNow + Double(spoilerDelay)) }
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
