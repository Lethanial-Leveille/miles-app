import AVFoundation

// Plays what /speak returns. play(_:) returns when Nova stops talking, whether she finished,
// was cut off with stop(), or the task awaiting her was cancelled, so a loop can simply await her.
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?

    // How loud she is right now, 0 to 1, on the same scale as SpeechService.inputLevel
    var level: Float {
        guard let player, player.isPlaying else { return 0 }
        player.updateMeters()
        let decibels = player.averagePower(forChannel: 0)
        return min(max((decibels + 50) / 50, 0), 1)
    }

    func play(_ audio: Data) async throws {
        stop()
        let player = try AVAudioPlayer(data: audio)
        player.delegate = self
        player.isMeteringEnabled = true
        self.player = player

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                finished = continuation
                // play() answers false when the audio can not start, and then no delegate call follows
                if !player.play() { finish(ObjectIdentifier(player)) }
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    // Cutting her off sends no delegate call, so this ends the wait itself
    func stop() {
        guard let player else { return }
        player.stop()
        finish(ObjectIdentifier(player))
    }

    // Only the player now playing may end the wait. A late callback from one already stopped
    // would otherwise end the next reply before it started.
    private func finish(_ which: ObjectIdentifier) {
        guard let player, ObjectIdentifier(player) == which else { return }
        self.player = nil
        let waiting = finished
        finished = nil
        waiting?.resume()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let which = ObjectIdentifier(player)
        Task { @MainActor in self.finish(which) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let which = ObjectIdentifier(player)
        Task { @MainActor in self.finish(which) }
    }
}
