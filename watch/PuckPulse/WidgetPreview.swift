#if DEBUG
import SwiftUI

/// Simulator check for the Smart Stack card: launching with `-widgetPreview YES` shows the card
/// at this watch's accessoryRectangular size for a few game states, clipped like the real widget.
struct WidgetPreview: View {
    /// accessoryRectangular size by screen width, from Apple's watchOS widget size table.
    private static let sizes: [CGFloat: CGSize] = [
        162: CGSize(width: 150, height: 47), // 40 mm
        176: CGSize(width: 157, height: 50), // 41 mm
        184: CGSize(width: 162, height: 50), // 44 mm
        187: CGSize(width: 165, height: 51), // 42 mm
        198: CGSize(width: 170, height: 54), // 45 mm
        205: CGSize(width: 179, height: 56), // 49 mm
        208: CGSize(width: 178, height: 56), // 46 mm
    ]

    private var size: CGSize {
        let width = WKInterfaceDevice.current().screenBounds.width
        return Self.sizes[width] ?? Self.sizes.min { abs($0.key - width) < abs($1.key - width) }!.value
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(Self.samples.enumerated()), id: \.offset) { _, state in
                GameCardView(state: state, date: .now, showLogos: true)
                    .frame(width: size.width, height: size.height, alignment: .leading)
                    .clipped()
                    .background(LinearGradient(colors: [Color(red: 0, green: 0.16, blue: 0.42), Color(red: 0, green: 0.07, blue: 0.2)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Rectangle().stroke(.yellow.opacity(0.6), lineWidth: 0.5))
            }
        }
    }

    private static let samples: [WidgetState] = {
        let now = Date().timeIntervalSinceReferenceDate
        let base: [String: Any] = ["gameID": 1, "team": "EDM", "opponent": "CGY", "isHome": true,
                                   "startTime": now - 3600, "liveModeOn": false, "spoilerDelay": 0, "updated": now,
                                   "isLive": true, "isFinished": false, "teamScore": 3, "opponentScore": 2,
                                   "status": "2nd 12:34", "lastGoal": "EDM McDavid (4) · 2nd 08:12"]
        let variants: [[String: Any]] = [
            [:],                                                                    // live, Go Live prompt
            ["liveModeOn": true, "penalty": "PP 5v4 1:23 · Backlund slashing"],     // live with a penalty
            ["isLive": false, "startTime": now + 30 * 3600, "teamScore": NSNull(),  // next game
             "opponentScore": NSNull(), "status": NSNull(), "lastGoal": NSNull()],
        ]
        return variants.compactMap { variant in
            let dict = base.merging(variant) { $1 }
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? JSONDecoder().decode(WidgetState.self, from: data)
        }
    }()
}
#endif
