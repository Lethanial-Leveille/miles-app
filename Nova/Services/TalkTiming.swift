import Foundation

// Where the time goes in one Talk Mode turn, from his last words to Nova's voice. Each mark
// keeps the first time it is set, and line(turn:) prints the turn as one line for the console,
// every step as the time since the step before it.
struct TalkTiming {

    enum Mark: CaseIterable {
        case speechEnd, transcriptFinal, chatSent, firstDelta, done, speakSent, firstAudio, playbackStart

        // Named for the wait that ends at this mark
        var label: String {
            switch self {
            case .speechEnd:       return "heard"
            case .transcriptFinal: return "silence wait"
            case .chatSent:        return "to send"
            case .firstDelta:      return "first delta"
            case .done:            return "done"
            case .speakSent:       return "to speak"
            case .firstAudio:      return "first audio"
            case .playbackStart:   return "playing"
            }
        }
    }

    private var times: [Mark: ContinuousClock.Instant] = [:]

    mutating func mark(_ mark: Mark, at instant: ContinuousClock.Instant = .now) {
        if times[mark] == nil { times[mark] = instant }
    }

    func has(_ mark: Mark) -> Bool { times[mark] != nil }

    // "[Nova] Talk turn 3: silence wait 2004 | to send 3 | first delta 1530 | ... | total 6120 ms"
    // A step that never happened, like audio after a failed /speak, shows a dash
    func line(turn: Int) -> String {
        guard let start = times[.speechEnd] else { return "[Nova] Talk turn \(turn): nothing heard" }
        var previous = start
        var last = start
        var steps: [String] = []
        for mark in Mark.allCases.dropFirst() {
            guard let time = times[mark] else {
                steps.append("\(mark.label) -")
                continue
            }
            steps.append("\(mark.label) \(Self.milliseconds(time - previous))")
            previous = time
            last = time
        }
        return "[Nova] Talk turn \(turn): " + steps.joined(separator: " | ")
            + " | total \(Self.milliseconds(last - start)) ms"
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
