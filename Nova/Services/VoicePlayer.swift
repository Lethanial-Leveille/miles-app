import AVFoundation
import AudioToolbox

// Plays what /speak streams, starting on the first chunk instead of waiting for the whole mp3.
// AudioFileStream finds the mp3 frames in whatever bytes have arrived, AVAudioConverter decodes
// them, and an AVAudioPlayerNode plays each piece as soon as it is scheduled. play returns when
// Nova stops talking, whether she finished, was cut off with stop(), or the task awaiting her
// was cancelled, so a loop can simply await her.
final class VoicePlayer {

    enum VoiceError: LocalizedError {
        case unreadable
        var errorDescription: String? { "The audio from the Pi could not be read." }
    }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var metering = false

    // One reply's state, made fresh by play
    private var parser: AudioFileStreamID?
    private var compressedFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var reader: Task<Void, Never>?
    private var finished: CheckedContinuation<Void, Never>?
    private var failure: Error?
    private var onStart: (() -> Void)?
    // Pieces scheduled and not yet heard, and whether the download has ended
    private var queued = 0
    private var arrived = false
    private var started = false
    // Bumped whenever a reply ends, so a late callback from one already stopped is ignored
    // instead of ending the next reply before it started
    private var reply = 0

    // How loud she is right now, 0 to 1, on the same scale as SpeechService.inputLevel
    private(set) var level: Float = 0

    init() {
        engine.attach(node)
    }

    // onFirstAudio runs when the first bytes arrive, onStart when her first words go to the
    // speaker. Throws only when she never started; a download that breaks after that just
    // ends her early, the same as the Pi's own contract for /speak.
    func play(_ audio: AsyncThrowingStream<Data, Error>,
              onFirstAudio: @escaping () -> Void = {},
              onStart: @escaping () -> Void = {}) async throws {
        stop()
        let current = reply
        failure = nil
        queued = 0
        arrived = false
        started = false
        self.onStart = onStart

        var stream: AudioFileStreamID?
        let opened = AudioFileStreamOpen(Unmanaged.passUnretained(self).toOpaque(),
                                         { client, stream, property, _ in
                                             guard property == kAudioFileStreamProperty_ReadyToProducePackets else { return }
                                             let player = Unmanaged<VoicePlayer>.fromOpaque(client).takeUnretainedValue()
                                             // Parsing runs on the main actor, and calls back inside it
                                             MainActor.assumeIsolated { player.prepareDecoder(stream) }
                                         },
                                         { client, byteCount, packetCount, data, descriptions in
                                             let player = Unmanaged<VoicePlayer>.fromOpaque(client).takeUnretainedValue()
                                             MainActor.assumeIsolated {
                                                 player.decode(data, byteCount: byteCount, packetCount: packetCount,
                                                               descriptions: descriptions)
                                             }
                                         },
                                         kAudioFileMP3Type, &stream)
        guard opened == noErr, let stream else { throw VoiceError.unreadable }
        parser = stream

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                finished = continuation
                reader = Task {
                    do {
                        var first = true
                        for try await chunk in audio {
                            guard current == reply else { return }
                            if first {
                                first = false
                                onFirstAudio()
                            }
                            parse(chunk)
                        }
                        guard current == reply else { return }
                        drain()
                    } catch {
                        guard current == reply else { return }
                        failure = error
                    }
                    arrived = true
                    finishIfHeard()
                }
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }

        if let failure, !started { throw failure }
    }

    // Cuts her off, drops the rest of the download, and lets play return
    func stop() {
        reply += 1
        reader?.cancel()
        reader = nil
        node.stop()
        if let parser { AudioFileStreamClose(parser) }
        parser = nil
        converter = nil
        compressedFormat = nil
        level = 0
        let waiting = finished
        finished = nil
        waiting?.resume()
    }

    // MARK: Decoding

    private func parse(_ chunk: Data) {
        guard let parser else { return }
        chunk.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = AudioFileStreamParseBytes(parser, UInt32(raw.count), base, [])
        }
    }

    // The parser has read the mp3 header, so the decoder and the engine can be set up for it
    private func prepareDecoder(_ stream: AudioFileStreamID) {
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &description) == noErr,
              let compressed = AVAudioFormat(streamDescription: &description),
              let decoded = AVAudioFormat(standardFormatWithSampleRate: description.mSampleRate,
                                          channels: description.mChannelsPerFrame),
              let converter = AVAudioConverter(from: compressed, to: decoded) else {
            failure = VoiceError.unreadable
            return
        }
        compressedFormat = compressed
        self.converter = converter

        if connectedFormat != decoded {
            engine.connect(node, to: engine.mainMixerNode, format: decoded)
            connectedFormat = decoded
        }
        if !metering {
            metering = true
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                guard let self else { return }
                let level = SpeechService.level(of: buffer)
                Task { @MainActor in self.level = level }
            }
        }
        // A route change, like AirPods connecting, stops the engine, so check every reply
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                failure = error
                self.converter = nil
            }
        }
    }

    private func decode(_ data: UnsafeRawPointer, byteCount: UInt32, packetCount: UInt32,
                        descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard let compressedFormat, let converter, let descriptions, packetCount > 0 else { return }

        var largest: UInt32 = 0
        for i in 0..<Int(packetCount) { largest = max(largest, descriptions[i].mDataByteSize) }
        let input = AVAudioCompressedBuffer(format: compressedFormat, packetCapacity: packetCount,
                                            maximumPacketSize: Int(largest))
        // The parser's pointers only live for this call, so the bytes are copied out now
        input.data.copyMemory(from: data, byteCount: Int(byteCount))
        input.byteLength = byteCount
        input.packetCount = packetCount
        input.packetDescriptions?.update(from: descriptions, count: Int(packetCount))

        let framesPerPacket = max(compressedFormat.streamDescription.pointee.mFramesPerPacket, 1)
        var given = false
        convert(using: converter, frames: packetCount * framesPerPacket) { status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return input
        }
    }

    // The decoder holds back a little of the end, so the last of it is asked for once the
    // download is complete
    private func drain() {
        guard let converter, let compressedFormat else { return }
        let framesPerPacket = max(compressedFormat.streamDescription.pointee.mFramesPerPacket, 1)
        convert(using: converter, frames: framesPerPacket * 4) { status in
            status.pointee = .endOfStream
            return nil
        }
    }

    private func convert(using converter: AVAudioConverter, frames: AVAudioFrameCount,
                         input: @escaping (UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer?) {
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frames) else { return }
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in input(status) }
        if status == .error {
            failure = error ?? VoiceError.unreadable
            return
        }
        if output.frameLength > 0 { schedule(output) }
    }

    // MARK: Playback

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        queued += 1
        let current = reply
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.heard(current) }
        }
        // She starts on the first piece. A late chunk is a short gap, never a stop.
        if !started {
            started = true
            node.play()
            onStart?()
        }
    }

    private func heard(_ which: Int) {
        guard which == reply else { return }
        queued -= 1
        finishIfHeard()
    }

    private func finishIfHeard() {
        if arrived && queued == 0 { stop() }
    }
}
