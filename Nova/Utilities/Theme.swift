import SwiftUI

enum Theme {

    // MARK: Backgrounds
    static let backgroundDark  = Color(red: 0.031, green: 0.035, blue: 0.055)
    static let backgroundLight = Color(red: 0.941, green: 0.953, blue: 0.980)

    static let surfaceDark  = Color(red: 0.063, green: 0.071, blue: 0.110)
    static let surfaceLight = Color(red: 0.980, green: 0.984, blue: 1.000)

    // MARK: Accents
    // Electric blue for dark mode, deeper navy-blue for light mode readability
    static let accentDark  = Color(red: 0.000, green: 0.706, blue: 1.000)
    static let accentLight = Color(red: 0.000, green: 0.333, blue: 0.800)

    // MARK: Text
    static let textPrimaryDark      = Color.white
    static let textPrimaryLight     = Color(red: 0.039, green: 0.059, blue: 0.149)

    static let textSecondaryDark    = Color(red: 0.557, green: 0.612, blue: 0.710)
    static let textSecondaryLight   = Color(red: 0.349, green: 0.400, blue: 0.541)

    // MARK: Gold — Nova Corps emblem color
    // Warm amber gold for identity elements (logo, emblem, brand marks)
    static let goldDark  = Color(red: 0.941, green: 0.706, blue: 0.169)
    static let goldLight = Color(red: 0.722, green: 0.525, blue: 0.043)

    static let goldGlowDark  = Color(red: 0.941, green: 0.706, blue: 0.169).opacity(0.40)
    static let goldGlowLight = Color(red: 0.722, green: 0.525, blue: 0.043).opacity(0.25)

    // MARK: Glow — blue system glow for interactive elements
    static let glowDark  = Color(red: 0.000, green: 0.706, blue: 1.000).opacity(0.35)
    static let glowLight = Color(red: 0.000, green: 0.333, blue: 0.800).opacity(0.20)

    // MARK: Convenience helpers
    // Pass colorScheme from the view and get back the right value automatically
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? backgroundDark : backgroundLight
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? surfaceDark : surfaceLight
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accentDark : accentLight
    }

    static func gold(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? goldDark : goldLight
    }

    static func goldGlow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? goldGlowDark : goldGlowLight
    }

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? textPrimaryDark : textPrimaryLight
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? textSecondaryDark : textSecondaryLight
    }

    static func glow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? glowDark : glowLight
    }
}
