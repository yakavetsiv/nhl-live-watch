import SwiftUI
import WatchKit

/// Sizes are designed on the 49 mm Ultra (205 pt wide) and shrink with the screen,
/// down to about 0.8 on 40 mm watches, so every model keeps the same proportions.
enum Layout {
    static let scale: CGFloat = {
        let width = WKInterfaceDevice.current().screenBounds.width
        return min(1, max(0.78, width / 205))
    }()

    /// True on 40, 41 and 44 mm screens, where a few elements switch to a tighter layout.
    static let isCompact = WKInterfaceDevice.current().screenBounds.width < 185

    static func size(_ base: CGFloat) -> CGFloat { (base * scale).rounded() }
}

/// System font sized for this screen that also follows the user's text size setting.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(base: CGFloat, style: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: base * Layout.scale, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// `base` is the point size on the 49 mm Ultra at the default text size.
    func scaledFont(_ base: CGFloat, relativeTo style: Font.TextStyle = .body,
                    weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(base: base, style: style, weight: weight, design: design))
    }
}
