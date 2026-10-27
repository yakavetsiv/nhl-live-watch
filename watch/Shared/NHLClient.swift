import Foundation

/// Thin client for the public NHL web API (no key needed).
struct NHLClient {
    private let base = URL(string: "https://api-web.nhle.com/v1/")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(from: base.appendingPathComponent(path))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }

    /// The live game if there is one, otherwise the next upcoming game, otherwise the most recent one.
    func currentOrNextGame() async throws -> ScheduledGame? {
        let week: ClubWeek = try await get("club-schedule/\(Club.abbrev)/week/now")
        var games = week.games
        if !games.contains(where: { !$0.isFinished }), let next = week.nextStartDate {
            let nextWeek: ClubWeek = try await get("club-schedule/\(Club.abbrev)/week/\(next)")
            games += nextWeek.games
        }
        if let live = games.first(where: \.isLive) { return live }
        if let upcoming = games.filter({ !$0.isFinished }).min(by: { $0.startTimeUTC < $1.startTimeUTC }) {
            return upcoming
        }
        return games.max(by: { $0.startTimeUTC < $1.startTimeUTC })
    }

    /// Games that have not started yet this season, soonest first.
    func upcomingGames(limit: Int) async throws -> [ScheduledGame] {
        let season: ClubWeek = try await get("club-schedule-season/\(Club.abbrev)/now")
        return season.games
            .filter { !$0.isLive && !$0.isFinished && $0.startTimeUTC > Date() }
            .sorted { $0.startTimeUTC < $1.startTimeUTC }
            .prefix(limit)
            .map { $0 }
    }

    func playByPlay(gameID: Int) async throws -> PlayByPlay {
        try await get("gamecenter/\(gameID)/play-by-play")
    }
}
