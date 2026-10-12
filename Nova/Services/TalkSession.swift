import Foundation
import Combine

// Talk Mode: listen, send, hear Nova answer in her own voice, then wait for a tap before
// listening again, so a room going quiet after her answer is never taken as his next turn.
// Every turn goes through the same ChatService as typing, so the conversation is in the chat
// afterwards and a calendar question asked out loud can be answered by typing, or the reverse.
final class TalkSession: ObservableObject {

    enum Phase {
        case starting, listening, thinking, speaking, waiting, stopped
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
    // Held while waiting for the tap that starts his next turn
    private var tapped: CheckedContinuation<Void, Never>?
    // Set by a tap that cuts Nova off: he tapped to talk, so the next turn starts at once
    private var cutIn = false
    // The turn being timed, logged as one line when it ends
    private var timing: TalkTiming?
    private var turns = 0
    private var subscriptions = Set<AnyCancellable>()

    // The pause that ends his turn. The chat mic waits 2 seconds, which out loud is a long
    // silence before anything happens; a tap still sends at once.
    private let silenceWait: TimeInterval = 1.2
    // Family names the recognizer otherwise hears as other words
    private let names = ["Lethanial", "Maj", "Majelin", "Caiah", "Micaiah", "Lahna", "Mylahna",
                         "Bree", "Mabryel", "Celo", "Marcelo", "Malique", "Azarieyah"]

    init(chat: ChatService) {
        self.chat = chat
        speech.$transcript.assign(to: &$heard)
        // The first delta makes Nova's bubble, so a Nova message at the end of the chat after
        // the send is the first delta. Watching for it leaves ChatService untouched.
        chat.$messages
            .sink { [weak self] messages in
                guard messages.last?.role == .nova, self?.timing?.has(.chatSent) == true else { return }
                self?.timing?.mark(.firstDelta)
            }
            .store(in: &subscriptions)
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
        releaseTap()
        phase = .stopped
    }

    // One tap does whatever moves the conversation along: start his turn, send what was said
    // without waiting out the silence, or cut Nova off and listen
    func tap() {
        switch phase {
        case .waiting:   releaseTap()
        case .listening: speech.stopRecording()
        case .speaking:
            cutIn = true
            voice.stop()
        default:         break
        }
    }

    private func nextTap() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { tapped = $0 }
        } onCancel: {
            Task { @MainActor in self.releaseTap() }
        }
    }

    private func releaseTap() {
        let waiting = tapped
        tapped = nil
        waiting?.resume()
    }

    private func run() async {
        // Opening Talk Mode is the first tap
        var ready = true
        while !Task.isCancelled {
            if !ready {
                phase = .waiting
                await nextTap()
                guard !Task.isCancelled else { return }
            }
            ready = false

            phase = .listening
            guard let words = await speech.listen(silence: silenceWait, names: names) else {
                notice = speech.permissionDenied
                    ? "Microphone or speech recognition is off for Nova. Turn it on in Settings."
                    : "The microphone would not start."
                phase = .stopped
                return
            }
            guard !Task.isCancelled else { return }

            let heardAt = speech.lastHeardAt
            let message = words.trimmingCharacters(in: .whitespacesAndNewlines)
            // Nothing heard waits for a tap like any other turn, which also keeps a recognizer
            // that fails at once from spinning this loop
            if message.isEmpty { continue }

            turns += 1
            timing = TalkTiming()
            timing?.mark(.speechEnd, at: heardAt ?? .now)
            timing?.mark(.transcriptFinal)
            defer { logTurn() }

            phase = .thinking
            said = ""
            notice = nil
            // A turn that reached the Pi finishes there whatever happens here, so ending Talk
            // Mode mid turn must not cut the reply off in the chat. A task of its own is not
            // cancelled with this loop.
            let chat = self.chat
            timing?.mark(.chatSent)
            let reply = await Task { await chat.send(text: message, channel: .voice) }.value
            timing?.mark(.done)
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
            cutIn = false
            do {
                timing?.mark(.speakSent)
                let audio = try await APIService.speak(text: reply)
                guard !Task.isCancelled else { return }
                phase = .speaking
                // She starts on the first chunk, while the rest of the mp3 is still arriving
                try await voice.play(audio,
                                     onFirstAudio: { [weak self] in self?.timing?.mark(.firstAudio) },
                                     onStart: { [weak self] in self?.timing?.mark(.playbackStart) })
            } catch {
                // The reply is already in the chat. Only her voice is missing.
                notice = "Could not say it out loud. \(error.localizedDescription)"
            }
            ready = cutIn
        }
    }

    private func logTurn() {
        if let timing { print(timing.line(turn: turns)) }
        timing = nil
    }
}
