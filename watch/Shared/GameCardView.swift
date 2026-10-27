import SwiftUI
import WidgetKit

/// The Smart Stack card (accessoryRectangular). Lives in Shared so debug builds of the app can
/// render it at every watch's widget size.
struct GameCardView: View {
    let state: WidgetState
    let date: Date
    let showLogos: Bool

    private func started(_ s: WidgetState) -> Bool { s.isLive || s.isFinished }

    /// Smart Stack: logos and score, status line, then the active penalty, last goal or a Go Live prompt.
    /// The widget is about 47 pt tall on 40 mm watches and 58 pt on 49 mm, so smaller layouts follow
    /// the full one and the first that fits wins.
    var body: some View {
        let s = state
        ViewThatFits(in: .vertical) {
            rectangularLayout(s, logo: 26, score: 22, detail: true)
            rectangularLayout(s, logo: 20, score: 18, detail: true)
            rectangularLayout(s, logo: 18, score: 17, detail: false)
        }
    }

    private func rectangularLayout(_ s: WidgetState, logo: CGFloat, score: CGFloat, detail: Bool) -> some View {
        let wantsGoLive = !s.liveModeOn && !s.isFinished && (s.isLive || s.startTime.timeIntervalSinceNow < 15 * 60)
        return VStack(alignment: .leading, spacing: logo >= 26 ? 3 : 1) {
            HStack(spacing: 6) {
                side(s.team, score: s.teamScore, started: started(s), bold: true, logo: logo, scoreSize: score)
                Spacer(minLength: 2)
                Text(started(s) ? "–" : (s.isHome ? "vs" : "@"))
                    .scaledFont(13, relativeTo: .footnote, weight: .semibold).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                side(s.opponent, score: s.opponentScore, started: started(s), bold: false, trailing: true,
                     logo: logo, scoreSize: score)
            }
            // Without room for a third line, the Go Live prompt replaces the status line.
            if detail || !wantsGoLive {
                statusLine(s).lineLimit(1).minimumScaleFactor(0.8)
            }
            if wantsGoLive {
                Label("Tap to Go Live", systemImage: "applewatch.radiowaves.left.and.right")
                    .scaledFont(12, relativeTo: .caption, weight: .semibold).foregroundStyle(Color(red: 0.4, green: 0.65, blue: 1))
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else if detail, let penalty = s.penalty {
                Label(penalty, systemImage: "exclamationmark.triangle.fill")
                    .scaledFont(11, relativeTo: .caption2).lineLimit(1).foregroundStyle(.orange)
            } else if detail, let goal = s.lastGoal {
                Label(goal, systemImage: "light.beacon.max.fill")
                    .scaledFont(11, relativeTo: .caption2).lineLimit(1).foregroundStyle(.secondary)
            } else if detail, s.liveModeOn {
                Label("Live taps on", systemImage: "checkmark.circle.fill")
                    .scaledFont(11, relativeTo: .caption2).foregroundStyle(.green)
            }
        }
    }

    /// LIVE with period and clock, FINAL, or the start time with a countdown.
    @ViewBuilder private func statusLine(_ s: WidgetState) -> some View {
        if s.isLive {
            HStack(spacing: 4) {
                LiveDot(size: 5)
                Text(s.status ?? "").monospacedDigit()
            }
            .scaledFont(12, relativeTo: .caption, weight: .semibold)
        } else if s.isFinished {
            Text(s.status ?? "FINAL").scaledFont(12, relativeTo: .caption, weight: .semibold).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                Text(s.startTime, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .scaledFont(12, relativeTo: .caption, weight: .semibold)
                if s.startTime > date {
                    Text("in \(s.startTime, style: .relative)")
                        .scaledFont(12, relativeTo: .caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Logo (or abbreviation on tinted faces) next to the score; the score sits toward the middle.
    private func side(_ abbrev: String, score: Int?, started: Bool, bold: Bool, trailing: Bool = false,
                      logo: CGFloat, scoreSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            if trailing, started { scoreText(score, size: scoreSize) }
            if showLogos {
                TeamLogo(abbrev: abbrev, size: logo)
            } else {
                Text(abbrev).scaledFont(14, relativeTo: .subheadline, weight: bold ? .heavy : .semibold, design: .rounded)
            }
            if !trailing, started { scoreText(score, size: scoreSize) }
        }
    }

    private func scoreText(_ score: Int?, size: CGFloat) -> some View {
        Text(score.map(String.init) ?? "–")
            .scaledFont(size, relativeTo: .title3, weight: .heavy, design: .rounded)
            .monospacedDigit()
            .widgetAccentable()
    }
}
