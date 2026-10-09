import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechService: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var permissionDenied = false

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    // How long a pause ends the recording. The chat mic keeps 2 seconds; Talk Mode passes its own.
    private var silenceWait: TimeInterval = 2.0
    // Held by listen() until the recording ends, whatever ended it
    private var finished: CheckedContinuation<String, Never>?

    // How loud the microphone is right now, 0 to 1. Not published: it changes dozens of times a
    // second, and the Talk Mode waveform reads it once per frame instead.
    private(set) var inputLevel: Float = 0
    // When the recognizer last had something new, the nearest thing to when he stopped talking
    private(set) var lastHeardAt: ContinuousClock.Instant?

    // One whole utterance: starts recording, and returns what was heard once the silence stop
    // or a cancel ends it. nil when the microphone could not start at all, so a caller looping
    // on this stops instead of spinning. names are words the recognizer should expect, like
    // family names it would otherwise hear as ordinary words.
    func listen(silence: TimeInterval, names: [String] = []) async -> String? {
        if isRecording { stopRecording() }
        await beginRecording(silence: silence, names: names)
        guard isRecording else { return nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { finished = $0 }
        } onCancel: {
            Task { @MainActor in self.stopRecording() }
        }
    }

    func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            await beginRecording(silence: 2.0, names: [])
        }
    }

    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        inputLevel = 0

        let waiting = finished
        finished = nil
        waiting?.resume(returning: transcript)
    }

    // MARK: Private

    private func beginRecording(silence: TimeInterval, names: [String]) async {
        guard await requestPermissions() else {
            permissionDenied = true
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // playAndRecord rather than record: record silences every player in the app, and
            // Talk Mode plays Nova's voice between turns without reconfiguring anything.
            // defaultToSpeaker because playAndRecord otherwise plays through the earpiece.
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            request.shouldReportPartialResults = true
            // On-device only — no audio leaves the phone
            request.requiresOnDeviceRecognition = true
            request.contextualStrings = names
            silenceWait = silence

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            // The tap runs on the audio thread, so it feeds the request it was given rather than
            // reading a property of this main actor object
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.level(of: buffer)
                Task { @MainActor in self?.inputLevel = level }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            transcript = ""
            lastHeardAt = nil

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor [self] in
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.lastHeardAt = .now
                        self.resetSilenceTimer()
                    }
                    if error != nil || result?.isFinal == true {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            stopRecording()
        }
    }

    // Restart the silence countdown each time new speech arrives
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceWait, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.stopRecording()
            }
        }
    }

    // Root mean square of the first channel, mapped from about -50 dB (a quiet room) up to 0.
    // VoicePlayer meters Nova's voice with it too, so both waveforms move on one scale.
    nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))
        return min(max((decibels + 50) / 50, 0), 1)
    }

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
