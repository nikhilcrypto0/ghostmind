import Foundation
import ScreenCaptureKit
import AVFoundation

class SystemAudioCapture: NSObject {
    static let shared = SystemAudioCapture()

    private var stream: SCStream?
    private(set) var isCapturing = false

    func start() {
        guard !isCapturing else { return }
        Task { await startCapture() }
    }

    func stop() {
        Task {
            try? await stream?.stopCapture()
            stream = nil
            isCapturing = false
            GhostLog.write("System audio capture stopped")
        }
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
            GhostLog.write("System audio capture started ✓ (interviewer voice enabled)")
        } catch {
            GhostLog.write("System audio capture failed: \(error.localizedDescription)")
        }
    }
}

extension SystemAudioCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.numSamples > 0 else { return }

        var bufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr,
              let dataPointer = bufferList.mBuffers.mData else { return }

        let byteCount = Int(bufferList.mBuffers.mDataByteSize)
        let floatCount = byteCount / MemoryLayout<Float>.size
        let floats = dataPointer.assumingMemoryBound(to: Float.self)

        var int16Samples = [Int16](repeating: 0, count: floatCount)
        for i in 0..<floatCount {
            int16Samples[i] = Int16(max(-32767.0, min(32767.0, floats[i] * 32767.0)))
        }

        let data = int16Samples.withUnsafeBytes { Data($0) }
        TranscriptionManager.shared.sendSystemAudio(data)
    }
}
