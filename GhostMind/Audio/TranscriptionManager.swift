import Foundation
import Speech
import AVFoundation

class TranscriptionManager: NSObject {
    static let shared = TranscriptionManager()

    private(set) var isReady = false
    private var sampleRate: Int = 48000
    private var usingDeepgram = false
    private var deepgramKey: String = ""

    // Dual Deepgram streams — mic = candidate, system = interviewer
    private var micStream: DeepgramStream?
    private var systemStream: DeepgramStream?
    private var hasNotifiedReady = false

    // Dialog log — chronological commits from both streams, labeled by source
    private struct DialogEntry {
        let timestamp: Date
        let source: DeepgramStream.Source
        let text: String
    }
    private var dialogLog: [DialogEntry] = []
    private let dialogQueue = DispatchQueue(label: "com.ghostmind.dialog")
    private let maxDialogEntries = 40

    // Apple Speech fallback (mic only — used when no Deepgram key)
    private let queue = DispatchQueue(label: "com.ghostmind.transcription", qos: .userInitiated)
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var appleTask: SFSpeechRecognitionTask?
    private var lastRestartTime = Date.distantPast
    private let minRestartInterval: TimeInterval = 2.0
    private var restartTimer: Timer?
    private var isRestarting = false
    private var appleRollingTranscript = ""
    private var appleCurrentSegment = ""
    private(set) var appleLastUtterance = ""

    func setup() {
        let engine = AVAudioEngine()
        let rate = Int(engine.inputNode.outputFormat(forBus: 0).sampleRate)
        sampleRate = rate > 8000 ? rate : 48000
        GhostLog.write("Input sample rate: \(sampleRate)Hz")

        if let key = loadDeepgramKey(), !key.isEmpty {
            deepgramKey = key
            usingDeepgram = true
            GhostLog.write("Deepgram \(AppConfig.deepgramModel) selected (dual stream)")
            setupDualStreams()
            requestMicAndConnect()
        } else {
            GhostLog.write("No Deepgram key — falling back to Apple Speech (mic only, no interviewer separation)")
            setupAppleSpeech()
        }
    }

    private func setupDualStreams() {
        let mic = DeepgramStream(source: .mic, apiKey: deepgramKey, sampleRate: sampleRate)
        let sys = DeepgramStream(source: .system, apiKey: deepgramKey, sampleRate: 48000)
        mic.delegate = self
        sys.delegate = self
        micStream = mic
        systemStream = sys
    }

    private func loadDeepgramKey() -> String? {
        if let k = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"], !k.isEmpty { return k }
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".deepgram_api_key")
        return try? String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestMicAndConnect() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                if granted {
                    AudioCaptureManager.shared.start()
                    self.micStream?.connect()
                    self.systemStream?.connect()
                } else {
                    NotificationCenter.default.post(name: .whisperReady, object: nil,
                        userInfo: ["error": "Microphone access denied"])
                }
            }
        }
    }

    // MARK: - Audio input

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        if usingDeepgram {
            sendBufferTo(stream: micStream, buffer: buffer)
        } else {
            queue.async { self.request?.append(buffer) }
        }
    }

    // Called by SystemAudioCapture — already-converted int16 little-endian PCM
    func sendSystemAudio(_ data: Data) {
        systemStream?.send(data)
    }

    // Called by SystemAudioCapture's heartbeat when ScreenCaptureKit has gone
    // idle. Forces Deepgram to flush any buffered partial as a final commit.
    func finalizeSystemStream() {
        systemStream?.flushFinalize()
    }

    private func sendBufferTo(stream: DeepgramStream?, buffer: AVAudioPCMBuffer) {
        guard let stream else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        let data: Data
        if let ch = buffer.floatChannelData?[0] {
            var samples = [Int16](repeating: 0, count: count)
            for i in 0..<count {
                samples[i] = Int16(max(-32767, min(32767, Int32(ch[i] * 32767))))
            }
            data = samples.withUnsafeBytes { Data($0) }
        } else if let ch = buffer.int16ChannelData?[0] {
            data = Data(bytes: ch, count: count * 2)
        } else {
            GhostLog.write("sendBufferTo: unsupported buffer format")
            return
        }
        stream.send(data)
    }

    // MARK: - Transcript access

    // Labeled dialog suitable for the Claude prompt
    func currentTranscript() -> String {
        if usingDeepgram {
            return dialogQueue.sync {
                dialogLog.map { "[\($0.source.rawValue)] \($0.text)" }.joined(separator: "\n")
            }
        } else {
            return queue.sync {
                (appleRollingTranscript + " " + appleCurrentSegment).trimmingCharacters(in: .whitespaces)
            }
        }
    }

    var lastInterviewerUtterance: String {
        systemStream?.lastUtterance ?? ""
    }

    var lastCandidateUtterance: String {
        if usingDeepgram {
            return micStream?.lastUtterance ?? ""
        } else {
            return queue.sync { appleLastUtterance }
        }
    }

    func resetTranscript() {
        dialogQueue.async { self.dialogLog.removeAll() }
        queue.async {
            self.appleRollingTranscript = ""
            self.appleCurrentSegment = ""
        }
        GhostLog.write("Transcript reset")
    }

    // MARK: - Apple Speech fallback (mic only)

    private func setupAppleSpeech() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            GhostLog.write("Apple Speech auth: \(status.rawValue)")
            DispatchQueue.main.async {
                if status == .authorized {
                    self?.isReady = true
                    self?.startAppleRecognition()
                    AudioCaptureManager.shared.start()
                    NotificationCenter.default.post(name: .whisperReady, object: nil)
                } else {
                    NotificationCenter.default.post(name: .whisperReady, object: nil,
                        userInfo: ["error": "Speech recognition not authorized"])
                }
            }
        }
    }

    private func startAppleRecognition() {
        guard !isRestarting else { return }
        guard let recognizer, recognizer.isAvailable else { return }

        let now = Date()
        guard now.timeIntervalSince(lastRestartTime) >= minRestartInterval else {
            let delay = minRestartInterval - now.timeIntervalSince(lastRestartTime)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.startAppleRecognition()
            }
            return
        }
        isRestarting = true
        lastRestartTime = now

        let pending = applePendingSegment()
        if !pending.isEmpty { commitApple(pending) }

        appleTask?.cancel(); appleTask = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        queue.sync { self.request = req }

        appleTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    let final = text.isEmpty ? self.applePendingSegment() : text
                    if !final.isEmpty {
                        self.commitApple(final)
                    } else {
                        self.queue.async { self.appleCurrentSegment = "" }
                    }
                    self.isRestarting = false
                    DispatchQueue.main.async { self.startAppleRecognition() }
                } else {
                    self.updateApplePartial(text)
                }
            }
            if let err = error as NSError?, err.code != 301 {
                if err.code == 1110 {
                    let p = self.applePendingSegment()
                    if !p.isEmpty { self.commitApple(p) }
                    self.isRestarting = false
                    DispatchQueue.main.async { self.startAppleRecognition() }
                } else {
                    GhostLog.write("Apple Speech error \(err.code): \(err.localizedDescription)")
                    self.isRestarting = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startAppleRecognition() }
                }
            }
        }

        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 55, repeats: false) { [weak self] _ in
            self?.isRestarting = false
            self?.startAppleRecognition()
        }
        GhostLog.write("Apple Speech session started")
    }

    private func applePendingSegment() -> String {
        queue.sync { appleCurrentSegment }
    }

    private func updateApplePartial(_ text: String) {
        queue.async {
            self.appleCurrentSegment = text
            // No question detection on partials in Apple Speech path — only commits.
        }
    }

    private func commitApple(_ text: String) {
        queue.async {
            GhostLog.write("Apple Commit: \"\(text)\"")
            self.appleRollingTranscript = String((self.appleRollingTranscript + " " + text)
                .trimmingCharacters(in: .whitespaces)
                .suffix(AppConfig.maxTranscriptLength))
            self.appleCurrentSegment = ""
            self.appleLastUtterance = text
            let full = self.appleRollingTranscript
            // Apple Speech path can't tell interviewer from candidate — treat all as questions.
            // This is the degraded fallback when no Deepgram key is configured.
            QuestionDetector.shared.fireIfQuestion(transcript: full, latestUtterance: text) { transcript, mode in
                AgentRouter.shared.handle(transcript: transcript, mode: mode)
            }
        }
    }
}

// MARK: - Deepgram dual-stream delegate

extension TranscriptionManager: DeepgramStreamDelegate {
    func deepgramStreamDidOpen(_ stream: DeepgramStream) {
        GhostLog.write("Stream open: \(stream.source.rawValue)")
        // Fire whisperReady once — mic open is sufficient (system stream may take longer)
        guard !hasNotifiedReady else { return }
        hasNotifiedReady = true
        isReady = true
        NotificationCenter.default.post(name: .whisperReady, object: nil)
    }

    func deepgramStream(_ stream: DeepgramStream, didProducePartial text: String) {
        // Partial-based detection disabled in dual-stream mode — only fire on commits.
        // But we need to tell SystemAudioCapture about interviewer partials so its
        // idle-finalize heartbeat knows when an utterance is in flight.
        if stream.source == .system, !text.isEmpty {
            SystemAudioCapture.shared.notePartialReceived()
        }
    }

    func deepgramStream(_ stream: DeepgramStream, didCommitSegment text: String) {
        dialogQueue.sync {
            dialogLog.append(DialogEntry(timestamp: Date(), source: stream.source, text: text))
            if dialogLog.count > maxDialogEntries {
                dialogLog.removeFirst(dialogLog.count - maxDialogEntries)
            }
        }

        // ONLY interviewer commits trigger question detection.
        // Candidate (mic) commits stay as conversational context only.
        guard stream.source == .system else { return }

        // Tell the system-audio heartbeat we got a real final so it doesn't
        // try to force another Finalize right after.
        SystemAudioCapture.shared.noteFinalReceived()

        let dialog = currentTranscript()
        QuestionDetector.shared.fireIfQuestion(transcript: dialog, latestUtterance: text) { transcript, mode in
            AgentRouter.shared.handle(transcript: transcript, mode: mode)
        }
    }
}
