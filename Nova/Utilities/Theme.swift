import SwiftUI

enum Theme {
    // Pure black. On the phone's OLED screen those pixels are switched off, so anything lit
    // floats on nothing
    static let background    = Color.black
    // The greys below share the cyan's hue (186 degrees), so nothing neutral pulls against it
    static let surface       = Color(red: 0.055, green: 0.086, blue: 0.090)  // #0E1617

    // What Nova is doing, one colour each. Colour means state in this app, never decoration,
    // so a colour only appears when its state is true
    static let listening     = Color(red: 0.000, green: 0.898, blue: 1.000)  // #00E5FF
    static let thinking      = Color(red: 0.627, green: 0.400, blue: 1.000)  // #A066FF
    static let speaking      = Color(red: 1.000, green: 0.541, blue: 0.165)  // #FF8A2A
    static let alert         = Color(red: 1.000, green: 0.231, blue: 0.306)  // #FF3B4E
    // A true green, far enough from the cyan that a ticked box never reads as an unticked one
    static let done          = Color(red: 0.235, green: 0.867, blue: 0.392)  // #3CDD64

    // The resting colour is Nova listening: ready for you
    static let accent        = listening
    static let accentGlow    = listening.opacity(0.28)
    // Text or glyphs drawn on top of a filled accent or done button
    static let onAccent      = background

    // Text
    static let textPrimary   = Color(red: 0.933, green: 0.961, blue: 0.965)  // #EEF5F6
    static let textSecondary = Color(red: 0.471, green: 0.565, blue: 0.576)  // #789093
}
