import Foundation

/// One window of 16 kHz mono audio handed to the transcription engine.
struct AudioWindow: Sendable {
    let samples: [Float]
    let source: AudioSource
    /// Seconds since the recording started.
    let startTime: TimeInterval
}

/// Accumulates 16 kHz mono samples and emits fixed windows with overlap.
/// One instance per audio source (mic / system) — channels are windowed
/// independently. Owned by MeetingSession (MainActor), so no locking needed.
struct AudioChunker {
    static let sampleRate = 16_000
    /// 6 s window. Overlap defaults to 1 s (helps the local engine at
    /// window boundaries); the cloud engine uses 0 s so no speech is
    /// transcribed twice.
    private let windowSamples: Int
    private let hopSamples: Int

    init(windowSeconds: Int = 6, overlapSeconds: Int = 1) {
        self.windowSamples = windowSeconds * Self.sampleRate
        self.hopSamples = (windowSeconds - overlapSeconds) * Self.sampleRate
    }

    private var buffer: [Float] = []
    private var consumedSamples = 0

    /// Feed new samples; returns any windows that became complete.
    mutating func append(_ samples: [Float], source: AudioSource) -> [AudioWindow] {
        buffer.append(contentsOf: samples)
        var windows: [AudioWindow] = []
        while buffer.count >= windowSamples {
            windows.append(AudioWindow(
                samples: Array(buffer.prefix(windowSamples)),
                source: source,
                startTime: TimeInterval(consumedSamples) / TimeInterval(Self.sampleRate)
            ))
            buffer.removeFirst(hopSamples)
            consumedSamples += hopSamples
        }
        return windows
    }

    /// Flush the tail at stop: pad the remainder with silence so the last
    /// words still get transcribed.
    mutating func flush(source: AudioSource) -> AudioWindow? {
        guard !buffer.isEmpty else { return nil }
        var tail = buffer
        tail.append(contentsOf: [Float](repeating: 0, count: max(0, windowSamples - tail.count)))
        buffer.removeAll()
        return AudioWindow(
            samples: tail,
            source: source,
            startTime: TimeInterval(consumedSamples) / TimeInterval(Self.sampleRate)
        )
    }
}
