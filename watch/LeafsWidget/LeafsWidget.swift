import SwiftUI
import WidgetKit

// MARK: - Timeline

struct GameEntry: TimelineEntry {
    let date: Date
    let state: WidgetState?
    var relevance: TimelineEntryRelevance?
}

/// Builds the widget from what the app last shared. When that is stale and no spoiler delay is set,
/// it asks the NHL API itself so the widget still works without the app running.
struct GameProvider: TimelineProvider {
    private let client = NHLClient()

    func placeholder(in context: Context) -> GameEntry {
        GameEntry(date: .now, state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (GameEntry) -> Void) {
        completion(GameEntry(date: .now, state: WidgetState.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GameEntry>) -> Void) {
        Task {
            let state = await currentState()
            completion(timeline(for: state))
        }
    }

    private func currentState() async -> WidgetState? {
        let shared = WidgetState.load()
        let fresh = shared.map { Date().timeIntervalSince($0.updated) < 5 * 60 && !$0.isFinished } ?? false
        if fresh || (shared?.spoilerDelay ?? 0) > 0 && shared?.isFinished == false { return shared }
        var states: [WidgetState] = []
        for team in FollowedTeams.nhlAbbrevs {
            guard let game = try? await client.currentOrNextGame(team: team) else { continue }
            let live = game.isLive ? try? await client.playByPlay(gameID: game.id) : nil
            states.append(WidgetState(team: team, game: game, live: live,
                                      liveModeOn: shared?.gameID == game.id && shared?.liveModeOn == true,
                                      spoilerDelay: shared?.spoilerDelay ?? 0))
        }
        return states.min { $0.displayRank < $1.displayRank } ?? shared
    }

    private func timeline(for state: WidgetState?) -> Timeline<GameEntry> {
        let now = Date()
        guard let state else {
            return Timeline(entries: [GameEntry(date: now, state: nil)], policy: .after(now.addingTimeInterval(3600)))
        }
        // Push the widget up the Smart Stack from 15 min before puck drop until Live mode is on.
        let wantsAttention = !state.liveModeOn && !state.isFinished
        let windowStart = state.startTime.addingTimeInterval(-15 * 60)
        let windowEnd = state.startTime.addingTimeInterval(3.5 * 3600)
        let hot = TimelineEntryRelevance(score: 100, duration: windowEnd.timeIntervalSince(max(now, windowStart)))
        let cold = TimelineEntryRelevance(score: 0)

        if state.isLive || (now >= windowStart && now < windowEnd) {
            let entry = GameEntry(date: now, state: state, relevance: wantsAttention ? hot : cold)
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(state.liveModeOn ? 15 * 60 : 5 * 60)))
        }
        if now < windowStart {
            return Timeline(entries: [
                GameEntry(date: now, state: state, relevance: cold),
                GameEntry(date: windowStart, state: state, relevance: wantsAttention ? hot : cold),
            ], policy: .after(state.startTime.addingTimeInterval(5 * 60)))
        }
        return Timeline(entries: [GameEntry(date: now, state: state, relevance: cold)],
                        policy: .after(now.addingTimeInterval(3 * 3600)))
    }
}

// MARK: - Views

struct GameWidgetView: View {
    let entry: GameEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(URL(string: entry.state?.liveModeOn == true ? "leafslive://open" : "leafslive://golive"))
            .containerBackground(Color(red: 0, green: 32 / 255, blue: 91 / 255).gradient, for: .widget)
    }

    @ViewBuilder private var content: some View {
        if let s = entry.state {
            switch family {
            case .accessoryCircular: circular(s)
            case .accessoryInline: Text(inline(s))
            default: rectangular(s)
            }
        } else {
            Label("Hockey Live", systemImage: "hockey.puck.fill")
        }
    }

    private var matchup: (WidgetState) -> String {
        { "\($0.team) \($0.isHome ? "vs" : "@") \($0.opponent)" }
    }

    private func score(_ s: WidgetState) -> String {
        "\(s.teamScore.map(String.init) ?? "–")–\(s.opponentScore.map(String.init) ?? "–")"
    }

    private func inline(_ s: WidgetState) -> String {
        if s.isLive || s.isFinished { return "\(s.team) \(score(s)) \(s.opponent) \(s.status ?? "")" }
        return "\(matchup(s)) \(s.startTime.formatted(date: .omitted, time: .shortened))"
    }

    private func circular(_ s: WidgetState) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "hockey.puck.fill").font(.system(size: 10))
                if s.isLive || s.isFinished {
                    Text(score(s)).font(.system(size: 15, weight: .bold, design: .rounded))
                } else {
                    Text(s.startTime, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
    }

    private func rectangular(_ s: WidgetState) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(matchup(s)).font(.headline)
                Spacer()
                if s.isLive || s.isFinished {
                    Text(score(s)).font(.headline.monospacedDigit())
                }
            }
            if s.isLive || s.isFinished {
                HStack(spacing: 3) {
                    if s.isLive {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("LIVE").foregroundStyle(.red)
                    }
                    Text(s.status ?? "").foregroundStyle(s.isLive ? .primary : .secondary)
                }
                .font(.caption2.bold())
                if let penalty = s.penalty {
                    Text(penalty).font(.caption2).lineLimit(1)
                } else if let goal = s.lastGoal {
                    Text(goal).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                }
            } else {
                Text(s.startTime, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption2)
                if s.startTime > entry.date {
                    Text("in \(s.startTime, style: .relative)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !s.liveModeOn && !s.isFinished && (s.isLive || s.startTime.timeIntervalSinceNow < 15 * 60) {
                Label("Tap to Go Live", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.caption2).foregroundStyle(.tint)
            } else if s.liveModeOn {
                Label("Live taps on", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
            }
        }
    }
}

@main
struct LeafsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LeafsGame", provider: GameProvider()) { entry in
            GameWidgetView(entry: entry)
        }
        .configurationDisplayName("Next game")
        .description("Score, penalties and a Go Live shortcut.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
