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
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Logos only where colours survive (Smart Stack); tinted faces get abbreviations.
    private var showLogos: Bool { renderingMode == .fullColor }

    var body: some View {
        content
            .widgetURL(URL(string: entry.state?.liveModeOn == true ? "puckpulse://open" : "puckpulse://golive"))
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0, green: 0.16, blue: 0.42), Color(red: 0, green: 0.07, blue: 0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
    }

    @ViewBuilder private var content: some View {
        if let s = entry.state {
            switch family {
            case .accessoryCircular: circular(s)
            case .accessoryInline: Text(inline(s))
            default: rectangular(s)
            }
        } else {
            Label("Puck Pulse", systemImage: "hockey.puck.fill")
        }
    }

    private func started(_ s: WidgetState) -> Bool { s.isLive || s.isFinished }

    private func inline(_ s: WidgetState) -> String {
        if started(s) {
            return "\(s.team) \(s.teamScore.map(String.init) ?? "–")–\(s.opponentScore.map(String.init) ?? "–") \(s.opponent) \(s.status ?? "")"
        }
        return "\(s.team) \(s.isHome ? "vs" : "@") \(s.opponent) \(s.startTime.formatted(date: .omitted, time: .shortened))"
    }

    private func circular(_ s: WidgetState) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                TeamLogo(abbrev: s.opponent, size: 20, allowImage: showLogos)
                if started(s) {
                    Text("\(s.teamScore ?? 0)-\(s.opponentScore ?? 0)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.7)
                } else {
                    Text(s.startTime, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    /// Smart Stack: logos and score, status line, then the active penalty, last goal or a Go Live prompt.
    private func rectangular(_ s: WidgetState) -> some View {
        let wantsGoLive = !s.liveModeOn && !s.isFinished && (s.isLive || s.startTime.timeIntervalSinceNow < 15 * 60)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                side(s.team, score: s.teamScore, started: started(s), bold: true)
                Spacer(minLength: 2)
                Text(started(s) ? "–" : (s.isHome ? "vs" : "@"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                side(s.opponent, score: s.opponentScore, started: started(s), bold: false, trailing: true)
            }
            Group {
                if s.isLive {
                    HStack(spacing: 4) {
                        LiveDot(size: 5)
                        Text(s.status ?? "").monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .semibold))
                } else if s.isFinished {
                    Text(s.status ?? "FINAL").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text(s.startTime, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .font(.system(size: 12, weight: .semibold))
                        if s.startTime > entry.date {
                            Text("in \(s.startTime, style: .relative)")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                }
            }
            if wantsGoLive {
                Label("Tap to Go Live", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(red: 0.4, green: 0.65, blue: 1))
            } else if let penalty = s.penalty {
                Label(penalty, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).lineLimit(1).foregroundStyle(.orange)
            } else if let goal = s.lastGoal {
                Label(goal, systemImage: "light.beacon.max.fill")
                    .font(.system(size: 11)).lineLimit(1).foregroundStyle(.secondary)
            } else if s.liveModeOn {
                Label("Live taps on", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.green)
            }
        }
    }

    /// Logo (or abbreviation on tinted faces) next to the score; the score sits toward the middle.
    private func side(_ abbrev: String, score: Int?, started: Bool, bold: Bool, trailing: Bool = false) -> some View {
        HStack(spacing: 6) {
            if trailing, started { scoreText(score) }
            if showLogos {
                TeamLogo(abbrev: abbrev, size: 26)
            } else {
                Text(abbrev).font(.system(size: 14, weight: bold ? .heavy : .semibold, design: .rounded))
            }
            if !trailing, started { scoreText(score) }
        }
    }

    private func scoreText(_ score: Int?) -> some View {
        Text(score.map(String.init) ?? "–")
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .widgetAccentable()
    }
}

@main
struct PuckPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PuckPulseGame", provider: GameProvider()) { entry in
            GameWidgetView(entry: entry)
        }
        .configurationDisplayName("Next game")
        .description("Score, penalties and a Go Live shortcut.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
