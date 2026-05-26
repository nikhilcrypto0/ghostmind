import Foundation
import ScreenCaptureKit
import AVFoundation

class SystemAudioCapture: NSObject {
    static let shared = SystemAudioCapture()

    private var stream: SCStream?
    private(set) var isCapturing = false

    // ScreenCaptureKit delivers audio buffers continuously (every ~10ms) — but
    // when the system is quiet they contain near-silence that Deepgram's VAD
    // does NOT endpoint on. So partials never become finals, the question
    // detector never fires, and Claude is never called.
    //
    // Fix: track the last time we saw a partial with non-empty text, and after
    // ~700ms of no partial movement, send Deepgram a Finalize message to flush
    // whatever it's buffered. This is the only reliable way to force end-of-
    // utterance when the source audio has no real silence gaps.
    private let stateQueue = DispatchQueue(label: "com.ghostmind.system-audio.state")
    private var lastPartialTime = Date.distantPast      // last time Deepgram emitted a partial with text
    private var lastFinalizeTime = Date.distantPast     // throttle Finalize to once per idle window
    private var heartbeatTimer: DispatchSourceTimer?    // DispatchSource fires reliably; Timer depends on RunLoop modes
    private let heartbeatInterval: TimeInterval = 0.3   // 300ms tick
    private let finalizeThreshold: TimeInterval = 1.5   // Finalize after 1.5s with no partial updates.
                                                        // Has to be longer than the typical inter-word gap
                                                        // Deepgram allows between partial updates, otherwise
                                                        // we chop mid-sentence. 1.5s is well past Deepgram's
                                                        // own 400ms endpointing target, so Deepgram normally
                                                        // emits its own final first; we only kick in when
                                                        // it has buffered audio with no real silence.

    func start() {
        guard !isCapturing else { return }
        Task { await startCapture() }
    }

    func stop() {
        Task {
            try? await stream?.stopCapture()
            stream = nil
            isCapturing = false
            stopHeartbeat()
            GhostLog.write("System audio capture stopped")
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
        timer.setEventHandler { [weak self] in self?.tickHeartbeat() }
        timer.resume()
        heartbeatTimer = timer
        GhostLog.write("SystemAudio: heartbeat started (interval \(Int(heartbeatInterval * 1000))ms)")
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    // Runs on stateQueue (set by DispatchSourceTimer's queue).
    private func tickHeartbeat() {
        // No partial activity yet → nothing buffered to flush.
        guard lastPartialTime != .distantPast else { return }

        let now = Date()
        let idleFor = now.timeIntervalSince(lastPartialTime)
        let sinceLastFinalize = now.timeIntervalSince(lastFinalizeTime)

        // Flush once per idle window. Once we Finalize, partials reset to empty
        // and lastPartialTime won't advance until the next utterance, so this
        // naturally rate-limits itself without a separate cooldown.
        guard idleFor > finalizeThreshold, sinceLastFinalize > finalizeThreshold else { return }

        lastFinalizeTime = now
        lastPartialTime = .distantPast      // wait for next utterance before next flush
        GhostLog.write("SystemAudio: sending Finalize (no partial movement for \(String(format: "%.2f", idleFor))s)")
        TranscriptionManager.shared.finalizeSystemStream()
    }

    // Called by TranscriptionManager whenever Deepgram emits a partial with
    // non-empty text on the system stream. This is what we use to detect that
    // an utterance is in flight and ready to be flushed when it stops moving.
    func notePartialReceived() {
        stateQueue.async { self.lastPartialTime = Date() }
    }

    // Called when Deepgram naturally emits a final — clears the in-flight
    // marker so the heartbeat doesn't try to force a redundant Finalize.
    func noteFinalReceived() {
        stateQueue.async { self.lastPartialTime = .distantPast }
    }

    private func startCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                GhostLog.write("System audio: no display found")
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 1
            // Minimal video to reduce overhead
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
            try await stream?.startCapture()
            isCapturing = true
            startHeartbeat()
            GhostLog.write("System audio capture started ✓ (interviewer voice enabled)")
        } catch {
            GhostLog.write("System audio capture failed: \(error.localizedDescription)")
        }
    }
}

extension SystemAudioCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.numSamples > 0 else { return }

        // Query the required AudioBufferList size first — a stream with multiple
        // buffers (e.g. non-interleaved stereo) needs more than a single AudioBuffer.
        var sizeNeeded: Int = 0
        var blockBuffer: CMBlockBuffer?

        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr, sizeNeeded > 0 else { return }

        let listPtr = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: 16)
        defer { listPtr.deallocate() }
        let listTypedPtr = listPtr.assumingMemoryBound(to: AudioBufferList.self)

        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: listTypedPtr,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let abl = UnsafeMutableAudioBufferListPointer(listTypedPtr)
        guard let firstBuffer = abl.first, let dataPointer = firstBuffer.mData else { return }

        let byteCount = Int(firstBuffer.mDataByteSize)
        let floatCount = byteCount / MemoryLayout<Float>.size
        guard floatCount > 0 else { return }
        let floats = dataPointer.assumingMemoryBound(to: Float.self)

        var int16Samples = [Int16](repeating: 0, count: floatCount)
        for i in 0..<floatCount {
            int16Samples[i] = Int16(max(-32767.0, min(32767.0, floats[i] * 32767.0)))
        }

        let data = int16Samples.withUnsafeBytes { Data($0) }
        TranscriptionManager.shared.sendSystemAudio(data)
    }
}
