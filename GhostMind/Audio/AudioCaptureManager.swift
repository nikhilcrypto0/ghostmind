import AVFoundation
import Foundation

class AudioCaptureManager: NSObject {
    static let shared = AudioCaptureManager()

    private let audioEngine = AVAudioEngine()
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }

        let inputNode = audioEngine.inputNode
        // Remove any existing tap to avoid double-tap crash
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)

        GhostLog.write("Audio format: \(format.sampleRate)Hz, channels: \(format.channelCount)")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try audioEngine.start()
            isRunning = true
            GhostLog.write("Audio engine started ✓")
        } catch {
            GhostLog.write("Audio engine FAILED: \(error)")
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRunning = false
        GhostLog.write("Audio engine stopped")
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        TranscriptionManager.shared.appendBuffer(buffer)
    }
}
