import Foundation

/// The team the app follows. Change the abbreviation to follow another club.
enum Club {
    static let abbrev = "TOR"
    static let id = 10
}

// MARK: - Schedule (api-web.nhle.com/v1/club-schedule/TOR/week/...)

struct ClubWeek: Decodable {
    let nextStartDate: String?
    let games: [ScheduledGame]
}

struct ScheduledGame: Decodable, Identifiable, Equatable {
    let id: Int
    let startTimeUTC: Date
    let gameState: String
    let awayTeam: TeamRef
    let homeTeam: TeamRef

    var isLive: Bool { GameState.isLive(gameState) }
    var isFinished: Bool { GameState.isFinished(gameState) }
    var opponent: TeamRef { homeTeam.abbrev == Club.abbrev ? awayTeam : homeTeam }
    var leafsAreHome: Bool { homeTeam.abbrev == Club.abbrev }
}

struct TeamRef: Decodable, Equatable {
    let id: Int
    let abbrev: String
    let score: Int?
}

enum GameState {
    // FUT/PRE before puck drop, LIVE/CRIT during play, FINAL/OFF after.
    static func isLive(_ s: String) -> Bool { s == "LIVE" || s == "CRIT" }
    static func isFinished(_ s: String) -> Bool { s == "FINAL" || s == "OFF" }
}

// MARK: - Play-by-play (api-web.nhle.com/v1/gamecenter/{id}/play-by-play)

struct PlayByPlay: Decodable {
    let id: Int
    let gameState: String
    let startTimeUTC: Date
    let periodDescriptor: PeriodDescriptor?
    let clock: Clock?
    let situation: Situation?
    let awayTeam: PBPTeam
    let homeTeam: PBPTeam
    let plays: [Play]
    let rosterSpots: [RosterSpot]?
}

struct PBPTeam: Decodable {
    let id: Int
    let abbrev: String
    let score: Int?
    let sog: Int?
}

struct PeriodDescriptor: Decodable, Equatable {
    let number: Int
    let periodType: String // REG, OT, SO

    var label: String {
        switch periodType {
        case "OT": return number > 4 ? "\(number - 3)OT" : "OT"
        case "SO": return "SO"
        default: return ["1st", "2nd", "3rd"][safe: number - 1] ?? "P\(number)"
        }
    }
}

struct Clock: Decodable {
    let timeRemaining: String
    let running: Bool
    let inIntermission: Bool
}

struct Situation: Decodable {
    let situationCode: String
    let timeRemaining: String?
}

struct Play: Decodable {
    let eventId: Int
    let sortOrder: Int?
    let typeDescKey: String
    let timeInPeriod: String?
    let periodDescriptor: PeriodDescriptor?
    let details: PlayDetails?
}

struct PlayDetails: Decodable {
    let eventOwnerTeamId: Int?
    let scoringPlayerId: Int?
    let scoringPlayerTotal: Int?
    let assist1PlayerId: Int?
    let assist2PlayerId: Int?
    let awayScore: Int?
    let homeScore: Int?
    let committedByPlayerId: Int?
    let servedByPlayerId: Int?
    let descKey: String?
    let typeCode: String?
    let duration: Int?
    let shotType: String?
}

struct RosterSpot: Decodable {
    let teamId: Int
    let playerId: Int
    let firstName: LocalizedName
    let lastName: LocalizedName
    let sweaterNumber: Int?
}

struct LocalizedName: Decodable {
    let `default`: String
}

extension PlayByPlay {
    var leafsAreHome: Bool { homeTeam.abbrev == Club.abbrev }
    var leafs: PBPTeam { leafsAreHome ? homeTeam : awayTeam }
    var opponent: PBPTeam { leafsAreHome ? awayTeam : homeTeam }

    /// Skater strength for the Leafs, e.g. "PP 5v4", "PK 4v5", "EN" or nil at even strength.
    /// situationCode digits: away goalie, away skaters, home skaters, home goalie.
    var strengthLabel: String? {
        guard let code = situation?.situationCode, code.count == 4 else { return nil }
        let d = code.compactMap { Int(String($0)) }
        guard d.count == 4 else { return nil }
        let (us, them) = leafsAreHome ? (d[2], d[1]) : (d[1], d[2])
        let ourGoalie = leafsAreHome ? d[3] : d[0]
        let theirGoalie = leafsAreHome ? d[0] : d[3]
        if theirGoalie == 0 { return "EMPTY NET" }
        if ourGoalie == 0 { return "GOALIE PULLED" }
        if us > them { return "PP \(us)v\(them)" }
        if us < them { return "PK \(us)v\(them)" }
        return us < 5 ? "\(us)v\(them)" : nil
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
