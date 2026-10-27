import Foundation

enum EventKind: String, CaseIterable, Identifiable, Codable {
    case leafsGoal, opponentGoal, goalOverturned, powerPlay, leafsPenalty, period, final

    var id: String { rawValue }

    var settingTitle: String {
        switch self {
        case .leafsGoal: return "Leafs goal"
        case .opponentGoal: return "Opponent goal"
        case .goalOverturned: return "Goal overturned"
        case .powerPlay: return "Leafs power play"
        case .leafsPenalty: return "Leafs penalty"
        case .period: return "Period start / end"
        case .final: return "Final result"
        }
    }

    /// Lower number wins when several events arrive in one poll and only one haptic should play.
    var priority: Int {
        switch self {
        case .final: return 0
        case .leafsGoal: return 1
        case .opponentGoal: return 2
        case .goalOverturned: return 3
        case .powerPlay: return 4
        case .leafsPenalty: return 5
        case .period: return 6
        }
    }

    var symbol: String {
        switch self {
        case .leafsGoal: return "flag.checkered"
        case .opponentGoal: return "xmark.circle"
        case .goalOverturned: return "arrow.uturn.backward.circle"
        case .powerPlay: return "bolt.fill"
        case .leafsPenalty: return "exclamationmark.triangle"
        case .period: return "clock"
        case .final: return "trophy"
        }
    }
}

struct GameEvent: Identifiable, Equatable {
    let id = UUID()
    let kind: EventKind
    let title: String
    let detail: String
    let date = Date()
    /// For .final: true when the Leafs won.
    var won: Bool = false
    /// For .period: true at the end of a period, false at the start.
    var periodEnd: Bool = false
}

/// Compares two play-by-play snapshots and turns what changed into events.
struct EventDetector {
    private(set) var seenEventIDs = Set<Int>()
    private var lastSnapshot: PlayByPlay?
    private var announcedFinal = false

    mutating func reset() {
        seenEventIDs = []
        lastSnapshot = nil
        announcedFinal = false
    }

    /// The first snapshot of a game only records a baseline, so opening the app mid-game stays quiet.
    mutating func ingest(_ pbp: PlayByPlay) -> [GameEvent] {
        defer { lastSnapshot = pbp }
        guard let previous = lastSnapshot, previous.id == pbp.id else {
            reset()
            seenEventIDs = Set(pbp.plays.map(\.eventId))
            announcedFinal = GameState.isFinished(pbp.gameState)
            return []
        }

        let names = Dictionary(
            (pbp.rosterSpots ?? []).map { ($0.playerId, $0) },
            uniquingKeysWith: { a, _ in a })
        func name(_ id: Int?) -> String? {
            guard let id, let p = names[id] else { return nil }
            return p.lastName.default
        }

        var events: [GameEvent] = []
        let newPlays = pbp.plays
            .filter { !seenEventIDs.contains($0.eventId) }
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }

        // Score as of each play, so "End of 1st" shows the score at that moment.
        var running = (away: previous.awayTeam.score ?? 0, home: previous.homeTeam.score ?? 0)
        func scoreLine() -> String {
            let (us, them) = pbp.leafsAreHome ? (running.home, running.away) : (running.away, running.home)
            return "\(pbp.leafs.abbrev) \(us)–\(them) \(pbp.opponent.abbrev)"
        }

        for play in newPlays {
            seenEventIDs.insert(play.eventId)
            let d = play.details
            let ours = d?.eventOwnerTeamId == pbp.leafs.id
            let when = [play.periodDescriptor?.label, play.timeInPeriod].compactMap { $0 }.joined(separator: " ")

            switch play.typeDescKey {
            case "goal":
                running = (d?.awayScore ?? pbp.awayTeam.score ?? 0, d?.homeScore ?? pbp.homeTeam.score ?? 0)
                let score = scoreLine()
                var scorer = name(d?.scoringPlayerId) ?? (ours ? pbp.leafs.abbrev : pbp.opponent.abbrev)
                if let total = d?.scoringPlayerTotal { scorer += " (\(total))" }
                let assists = [name(d?.assist1PlayerId), name(d?.assist2PlayerId)].compactMap { $0 }
                let detail = [scorer, assists.isEmpty ? nil : "from " + assists.joined(separator: ", "), when]
                    .compactMap { $0 }.joined(separator: " · ")
                events.append(GameEvent(
                    kind: ours ? .leafsGoal : .opponentGoal,
                    title: ours ? "LEAFS GOAL! \(score)" : "\(pbp.opponent.abbrev) goal. \(score)",
                    detail: detail))

            case "penalty":
                let infraction = (d?.descKey ?? "penalty").replacingOccurrences(of: "-", with: " ").capitalized
                let minutes = d?.duration.map { "\($0) min" }
                let who = name(d?.committedByPlayerId) ?? name(d?.servedByPlayerId)
                let detail = [who, infraction, minutes, when].compactMap { $0 }.joined(separator: " · ")
                if ours {
                    events.append(GameEvent(kind: .leafsPenalty, title: "Leafs penalty", detail: detail))
                } else {
                    events.append(GameEvent(kind: .powerPlay, title: "Leafs power play", detail: detail))
                }

            case "period-start":
                let label = play.periodDescriptor?.label ?? "Period"
                let isOpening = play.periodDescriptor?.number == 1
                events.append(GameEvent(
                    kind: .period,
                    title: isOpening ? "Puck drop" : "\(label) underway",
                    detail: "\(pbp.leafs.abbrev) vs \(pbp.opponent.abbrev)"))

            case "period-end":
                let label = play.periodDescriptor?.label ?? "period"
                events.append(GameEvent(
                    kind: .period,
                    title: "End of \(label)",
                    detail: scoreLine(),
                    periodEnd: true))

            default:
                break
            }
        }

        // A goal taken off the board after review shows up only as a lower score.
        let prevTotal = (previous.awayTeam.score ?? 0) + (previous.homeTeam.score ?? 0)
        let total = (pbp.awayTeam.score ?? 0) + (pbp.homeTeam.score ?? 0)
        if total < prevTotal {
            events.append(GameEvent(
                kind: .goalOverturned,
                title: "Goal overturned",
                detail: "\(pbp.leafs.abbrev) \(pbp.leafs.score ?? 0)–\(pbp.opponent.score ?? 0) \(pbp.opponent.abbrev)"))
        }

        if !announcedFinal, GameState.isFinished(pbp.gameState) || pbp.plays.contains(where: { $0.typeDescKey == "game-end" }) {
            announcedFinal = true
            let us = pbp.leafs.score ?? 0, them = pbp.opponent.score ?? 0
            let suffix = pbp.periodDescriptor.map { $0.periodType == "REG" ? "" : " (\($0.periodType))" } ?? ""
            events.append(GameEvent(
                kind: .final,
                title: us > them ? "LEAFS WIN!" : "Leafs lose",
                detail: "Final\(suffix): \(pbp.leafs.abbrev) \(us)–\(them) \(pbp.opponent.abbrev)",
                won: us > them))
        }
        return events
    }
}
