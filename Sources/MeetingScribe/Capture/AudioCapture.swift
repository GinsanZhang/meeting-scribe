import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// One chunk of 16 kHz mono audio from a single source.
struct CapturedAudio: Sendable {
    let samples: [Float]
    let source: AudioSource
}

enum CaptureError: Error, LocalizedError {
    case noDisplay
    case converterUnavailable
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "找不到可录制的显示器"
        case .converterUnavailable: return "无法创建音频格式转换器"
        case .microphoneUnavailable: return "无法访问麦克风"
        }
    }
}

/// Captures microphone (AVAudioEngine) and, for online meetings, system audio
/// (ScreenCaptureKit). Both are converted to 16 kHz mono Float and delivered
/// on a single AsyncStream. One instance per recording session.
final class AudioCaptureEngine: NSObject, SCStreamDelegate, SCStreamOutput {
    private let engine = AVAudioEngine()
    private var stream: SCStream?
    private var micConverter: AVAudioConverter?
    private var systemConverter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    private let (audioStream, continuation) = AsyncStream<CapturedAudio>.makeStream()

    /// Starts capture and returns the stream of audio chunks.
    /// Call `stop()` to end the stream.
    func start(mode: MeetingMode) async throws -> AsyncStream<CapturedAudio> {
        try startMicrophone()
        if mode == .online {
            try await startSystemAudio()
        }
        return audioStream
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        if let stream {
            Task { try? await stream.stopCapture() }
            self.stream = nil
        }
        continuation.finish()
    }

    // MARK: - Microphone

    private func startMicrophone() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else { throw CaptureError.microphoneUnavailable }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw CaptureError.converterUnavailable
        }
        micConverter = converter
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.micConverter,
                  let samples = AudioSampleConverter.resampleTo16kMono(buffer, converter: converter)
            else { return }
            continuation.yield(CapturedAudio(samples: samples, source: .microphone))
        }
        engine.prepare()
        try engine.start()
    }

    // MARK: - System audio (ScreenCaptureKit)

    private func startSystemAudio() async throws {
        let content = try await SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }
        // Audio-only capture: no video frames are requested.
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(
            self, type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "meeting-scribe.system-audio")
        )
        try await stream.startCapture()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
        guard let pcmBuffer = AudioSampleConverter.pcmBuffer(from: sampleBuffer) else { return }
        if systemConverter == nil {
            systemConverter = AVAudioConverter(from: pcmBuffer.format, to: outputFormat)
        }
        guard let converter = systemConverter,
              let samples = AudioSampleConverter.resampleTo16kMono(pcmBuffer, converter: converter)
        else { return }
        continuation.yield(CapturedAudio(samples: samples, source: .system))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[MeetingScribe] system audio stream stopped: \(error)")
    }
}

/// Conversion helpers. The CMSampleBuffer path is the fiddliest interop in
/// the app; if the first Xcode build complains, look here first.
enum AudioSampleConverter {

    /// Resample any AVAudioPCMBuffer to 16 kHz mono Float via AVAudioConverter.
    static func resampleTo16kMono(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) -> [Float]? {
        let ratio = converter.outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            return nil
        }
        var error: NSError?
        var supplied = false
        converter.convert(to: outBuffer, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, outBuffer.frameLength > 0,
              let channelData = outBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outBuffer.frameLength)))
    }

    /// ScreenCaptureKit audio sample buffer -> AVAudioPCMBuffer at the
    /// buffer's native format (sample rate / channels preserved).
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else { return nil }
        let asbd = asbdPointer.pointee
        guard let format = AVAudioFormat(streamDescription: asbdPointer) else { return nil }

        let frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        pcmBuffer.frameLength = frameLength

        // Read the raw audio buffers (retained block buffer keeps memory alive).
        let listCapacity = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
        var listBytes = [UInt8](repeating: 0, count: listCapacity)
        var blockBuffer: CMBlockBuffer?
        let status = listBytes.withUnsafeMutableBytes { rawPtr in
            CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer, nil,
                rawPtr.baseAddress!.assumingMemoryBound(to: AudioBufferList.self),
                listCapacity, nil, nil, 0, &blockBuffer)
        }
        guard status == noErr else { return nil }

        let channelCount = Int(asbd.mChannelsPerFrame)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bytesPerSample = Int(asbd.mBitsPerChannel) / 8

        listBytes.withUnsafeMutableBytes { rawPtr in
            let listPtr = rawPtr.baseAddress!.assumingMemoryBound(to: AudioBufferList.self)
            let bufferCount = Int(listPtr.pointee.mNumberBuffers)
            withUnsafePointer(to: &listPtr.pointee.mBuffers) { buffersPtr in
                buffersPtr.withMemoryRebound(to: AudioBuffer.self, capacity: max(bufferCount, 1)) { buffers in
                    if isNonInterleaved {
                        // One AudioBuffer per channel.
                        for ch in 0..<min(channelCount, bufferCount) {
                            copyChannel(
                                from: buffers[ch], to: pcmBuffer, channel: ch,
                                frames: Int(frameLength), bytesPerSample: bytesPerSample, isFloat: isFloat
                            )
                        }
                    } else if bufferCount >= 1 {
                        // Single interleaved buffer: deinterleave into channels.
                        deinterleave(
                            from: buffers[0], to: pcmBuffer, channels: channelCount,
                            frames: Int(frameLength), bytesPerSample: bytesPerSample, isFloat: isFloat
                        )
                    }
                }
            }
        }
        return pcmBuffer
    }

    private static func copyChannel(
        from buffer: AudioBuffer, to pcmBuffer: AVAudioPCMBuffer, channel: Int,
        frames: Int, bytesPerSample: Int, isFloat: Bool
    ) {
        guard let src = buffer.mData else { return }
        let byteCount = min(Int(buffer.mDataByteSize), frames * bytesPerSample)
        if isFloat {
            guard let dst = pcmBuffer.floatChannelData?[channel] else { return }
            src.copyMemory(to: dst, byteCount: byteCount)
        } else {
            guard let dst = pcmBuffer.int16ChannelData?[channel] else { return }
            src.copyMemory(to: dst, byteCount: byteCount)
        }
    }

    private static func deinterleave(
        from buffer: AudioBuffer, to pcmBuffer: AVAudioPCMBuffer, channels: Int,
        frames: Int, bytesPerSample: Int, isFloat: Bool
    ) {
        guard let src = buffer.mData else { return }
        if isFloat {
            guard let dstChannels = pcmBuffer.floatChannelData else { return }
            src.withMemoryRebound(to: Float.self, capacity: frames * channels) { samples in
                for frame in 0..<frames {
                    for ch in 0..<channels {
                        dstChannels[ch][frame] = samples[frame * channels + ch]
                    }
                }
            }
        } else {
            guard let dstChannels = pcmBuffer.int16ChannelData else { return }
            src.withMemoryRebound(to: Int16.self, capacity: frames * channels) { samples in
                for frame in 0..<frames {
                    for ch in 0..<channels {
                        dstChannels[ch][frame] = samples[frame * channels + ch]
                    }
                }
            }
        }
    }
}
