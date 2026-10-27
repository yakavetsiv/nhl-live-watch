import Foundation

extension PlayByPlay {
    private func lastName(_ id: Int?) -> String? {
        guard let id else { return nil }
        return rosterSpots?.first(where: { $0.playerId == id })?.lastName.default
    }

    private var sortedPlays: [Play] { plays.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) } }

    /// "Nylander (9) · 3rd 06:06" for the latest goal, with the scoring team's abbreviation first.
    var lastGoalSummary: String? {
        guard let goal = sortedPlays.last(where: { $0.typeDescKey == "goal" }) else { return nil }
        let team = goal.details?.eventOwnerTeamId == homeTeam.id ? homeTeam.abbrev : awayTeam.abbrev
        var scorer = lastName(goal.details?.scoringPlayerId) ?? team
        if let total = goal.details?.scoringPlayerTotal { scorer += " (\(total))" }
        let when = [goal.periodDescriptor?.label, goal.timeInPeriod].compactMap { $0 }.joined(separator: " ")
        return "\(team) \(scorer) · \(when)"
    }

    /// "PP 5v4 1:23 · Backlund slashing" while teams are not at even strength.
    var activePenaltySummary: String? {
        guard GameState.isLive(gameState), let strength = strengthLabel,
              strength.hasPrefix("PP") || strength.hasPrefix("PK") || strength.contains("v") else { return nil }
        var parts = [strength]
        if let left = situation?.timeRemaining { parts[0] += " \(left.hasPrefix("0") ? String(left.dropFirst()) : left)" }
        if let penalty = sortedPlays.last(where: { $0.typeDescKey == "penalty" }) {
            let who = lastName(penalty.details?.committedByPlayerId) ?? lastName(penalty.details?.servedByPlayerId)
            let what = penalty.details?.descKey?.replacingOccurrences(of: "-", with: " ")
            let text = [who, what].compactMap { $0 }.joined(separator: " ")
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: " · ")
    }

    /// "2nd 12:34", "INT 2nd", "FINAL" or "FINAL/OT".
    var statusLabel: String {
        if GameState.isFinished(gameState) {
            let type = periodDescriptor?.periodType ?? "REG"
            return type == "REG" ? "FINAL" : "FINAL/\(type)"
        }
        guard GameState.isLive(gameState) else { return "PRE" }
        let period = periodDescriptor?.label ?? ""
        if clock?.inIntermission == true { return "INT \(period)" }
        return "\(period) \(clock?.timeRemaining ?? "")"
    }
}

/// What the app hands the widget through the shared App Group.
struct WidgetState: Codable, Equatable {
    var gameID: Int
    var opponent: String
    var leafsAreHome: Bool
    var startTime: Date
    var leafsScore: Int?
    var opponentScore: Int?
    var status: String?
    var isLive: Bool
    var isFinished: Bool
    var lastGoal: String?
    var penalty: String?
    var liveModeOn: Bool
    var spoilerDelay: Int
    var updated: Date

    static let appGroup = "group.com.yakavetsiv.leafslive"
    private static let key = "widgetState"

    static func load() -> WidgetState? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetState.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }

    init(game: ScheduledGame, live: PlayByPlay?, liveModeOn: Bool, spoilerDelay: Int) {
        let pbp = live?.id == game.id ? live : nil
        gameID = game.id
        opponent = game.opponent.abbrev
        leafsAreHome = game.leafsAreHome
        startTime = game.startTimeUTC
        // With a spoiler delay only the delayed snapshot may show a score.
        let scheduleOK = spoilerDelay == 0
        leafsScore = pbp?.leafs.score ?? (scheduleOK ? (game.leafsAreHome ? game.homeTeam.score : game.awayTeam.score) : nil)
        opponentScore = pbp?.opponent.score ?? (scheduleOK ? game.opponent.score : nil)
        isLive = pbp.map { GameState.isLive($0.gameState) } ?? (scheduleOK && game.isLive)
        isFinished = pbp.map { GameState.isFinished($0.gameState) } ?? (scheduleOK && game.isFinished)
        status = pbp?.statusLabel
        lastGoal = pbp?.lastGoalSummary
        penalty = pbp?.activePenaltySummary
        self.liveModeOn = liveModeOn
        self.spoilerDelay = spoilerDelay
        updated = Date()
    }
}
