import SwiftUI

enum Theme {
    // Pure black. On the phone's OLED screen those pixels are switched off, so anything lit
    // floats on nothing
    static let background    = Color.black
    static let surface       = Color(red: 0.055, green: 0.067, blue: 0.090)  // #0E1117

    // What Nova is doing, one colour each. Colour means state in this app, never decoration,
    // so a colour only appears when its state is true
    static let listening     = Color(red: 0.239, green: 0.608, blue: 1.000)  // #3D9BFF
    static let thinking      = Color(red: 0.627, green: 0.400, blue: 1.000)  // #A066FF
    static let speaking      = Color(red: 1.000, green: 0.541, blue: 0.165)  // #FF8A2A
    static let alert         = Color(red: 1.000, green: 0.231, blue: 0.306)  // #FF3B4E
    static let done          = Color(red: 0.200, green: 0.878, blue: 0.541)  // #33E08A

    // The resting colour is Nova listening: ready for you
    static let accent        = listening
    static let accentGlow    = listening.opacity(0.28)

    // Text
    static let textPrimary   = Color(red: 0.933, green: 0.945, blue: 0.965)  // #EEF1F6
    static let textSecondary = Color(red: 0.471, green: 0.510, blue: 0.573)  // #788292
}
