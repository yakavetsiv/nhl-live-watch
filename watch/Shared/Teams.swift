import Foundation

enum League: String, Codable, CaseIterable {
    case nhl = "NHL"
    case ahl = "AHL"
}

struct Team: Codable, Hashable, Identifiable {
    let league: League
    let abbrev: String
    let name: String

    var id: String { "\(league.rawValue):\(abbrev)" }
}

/// The teams the user follows, shared with the widget through the App Group.
enum FollowedTeams {
    private static let key = "followedTeams"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetState.appGroup) }

    static func load() -> [Team] {
        guard let data = defaults?.data(forKey: key),
              let teams = try? JSONDecoder().decode([Team].self, from: data) else { return [] }
        return teams
    }

    static func save(_ teams: [Team]) {
        defaults?.set(try? JSONEncoder().encode(teams), forKey: key)
    }

    /// NHL abbreviations of followed teams, in the order the user picked them.
    static var nhlAbbrevs: [String] { load().filter { $0.league == .nhl }.map(\.abbrev) }
}
