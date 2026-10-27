import SwiftUI
import UIKit

/// Team logo on a white disc, or the abbreviation when logos were not fetched
/// (scripts/fetch-logos.sh) or the widget renders in a tinted watch face.
struct TeamLogo: View {
    let abbrev: String
    var size: CGFloat = 40
    /// Tinted watch faces flatten colours, so they get the abbreviation instead.
    var allowImage = true

    var body: some View {
        if allowImage, let image = UIImage(named: "logo-\(abbrev)") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(size * 0.14)
                .frame(width: size, height: size)
                .background(Circle().fill(.white))
        } else {
            Text(abbrev)
                .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(0.18)))
        }
    }
}

/// Red "● LIVE" marker.
struct LiveDot: View {
    var size: CGFloat = 6

    var body: some View {
        HStack(spacing: size * 0.6) {
            Circle().fill(.red).frame(width: size, height: size)
            Text("LIVE").foregroundStyle(.red)
        }
    }
}
