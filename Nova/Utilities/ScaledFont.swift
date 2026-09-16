import SwiftUI

// A fixed point size ignores the system text size setting. This keeps the size the design
// picked as the default, then grows or shrinks it the way the closest system text style would.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(near: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

    // Each text style has its own growth curve (captions grow less than body text),
    // so a 9pt label should scale like a caption, not like a paragraph
    private static func textStyle(near size: CGFloat) -> Font.TextStyle {
        switch size {
        case ...11: return .caption2
        case ...12: return .caption
        case ...14: return .footnote
        case ...15: return .subheadline
        case ...16: return .callout
        case ...19: return .body
        case ...21: return .title3
        case ...27: return .title2
        case ...33: return .title
        default:    return .largeTitle
        }
    }
}

extension View {
    func novaFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}
