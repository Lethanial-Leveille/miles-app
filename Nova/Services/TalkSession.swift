import Foundation
import Combine

// Talk Mode: listen, send, hear Nova answer in her own voice, listen again, until it is ended.
// Every turn goes through the same ChatService as typing, so the conversation is in the chat
// afterwards and a calendar question asked out loud can be answered by typing, or the reverse.
final class TalkSession: ObservableObject {

    enum Phase {
        case starting, listening, thinking, speaking, stopped
    }

    @Published private(set) var phase: Phase = .starting
    // What the microphone is hearing, live
    @Published private(set) var heard = ""
    // The reply being spoken, so a word she said too fast can still be read
    @Published private(set) var said = ""
    // Why the last turn did not end in her voice
    @Published private(set) var notice: String? = nil

    private let chat: ChatService
    private let speech = SpeechService()
    private let voice = VoicePlayer()
    private var loop: Task<Void, Never>?

    init(chat: ChatService) {
        self.chat = chat
        speech.$transcript.assign(to: &$heard)
    }

    // Loudness for the waveform: his voice while listening, hers while speaking
    var level: Float {
        switch phase {
        case .listening: return speech.inputLevel
        case .speaking:  return voice.level
        default:         return 0
        }
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { await run() }
    }

    func end() {
        loop?.cancel()
        loop = nil
        speech.stopRecording()
        voice.stop()
        phase = .stopped
    }

    // One tap does whatever moves the conversation along: send what was said without waiting
    // out the silence, or cut Nova off and go back to listening
    func tap() {
        switch phase {
        case .listening: speech.stopRecording()
        case .speaking:  voice.stop()
        default:         break
        }
    }

    private func run() async {
        while !Task.isCancelled {
            phase = .listening
            guard let words = await speech.listen() else {
                notice = speech.permissionDenied
                    ? "Microphone or speech recognition is off for Nova. Turn it on in Settings."
                    : "The microphone would not start."
                phase = .stopped
                return
            }
            guard !Task.isCancelled else { return }

            let message = words.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty {
                // A recognizer that fails at once would otherwise spin this loop flat out
                try? await Task.sleep(for: .milliseconds(300))
                continue
            }

            phase = .thinking
            said = ""
            notice = nil
            // A turn that reached the Pi finishes there whatever happens here, so ending Talk
            // Mode mid turn must not cut the reply off in the chat. A task of its own is not
            // cancelled with this loop.
            let chat = self.chat
            let reply = await Task { await chat.send(text: message, channel: .voice) }.value
            guard !Task.isCancelled else { return }

            guard let reply else {
                notice = chat.errorMessage ?? "The turn failed on the Pi."
                continue
            }
            guard !reply.isEmpty else {
                notice = "NOVA STAYED QUIET"
                continue
            }

            said = reply
            do {
                let audio = try await APIService.speak(text: reply)
                guard !Task.isCancelled else { return }
                phase = .speaking
                try await voice.play(audio)
            } catch {
                // The reply is already in the chat. Only her voice is missing.
                notice = "Could not say it out loud. \(error.localizedDescription)"
            }
        }
    }
}
