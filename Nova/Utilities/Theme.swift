import SwiftUI

enum Theme {
    // Three base colors
    static let background    = Color(red: 0.039, green: 0.043, blue: 0.063)
    static let surface       = Color(red: 0.075, green: 0.078, blue: 0.110)
    static let accent        = Color(red: 0.000, green: 0.898, blue: 1.000)  // #00E5FF
    static let accentGlow    = Color(red: 0.000, green: 0.898, blue: 1.000).opacity(0.28)

    // Text
    static let textPrimary   = Color(red: 0.925, green: 0.937, blue: 0.957)
    static let textSecondary = Color(red: 0.420, green: 0.478, blue: 0.553)
}
