import Foundation
import Speech
import AVFoundation

class TranscriptionManager: NSObject {
    static let shared = TranscriptionManager()

    private(set) var isReady = false
    private var rollingTranscript = ""
    private var currentSegment = ""
    private let maxTranscriptLength = AppConfig.maxTranscriptLength
    private let queue = DispatchQueue(label: "com.ghostmind.transcription", qos: .userInitiated)

    // Deepgram
    private var webSocketTask: URLSessionWebSocketTask?
    private var wsSession: URLSession?
    private var keepaliveTimer: Timer?
    private var sampleRate: Int = 48000
    private var usingDeepgram = false
    private var isConnecting = false
    private var hasNotifiedReady = false
    private var deepgramKey: String = ""

    // Apple Speech fallback
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var appleTask: SFSpeechRecognitionTask?
    private var lastRestartTime = Date.distantPast
    private let minRestartInterval: TimeInterval = 2.0
    private var restartTimer: Timer?
    private var isRestarting = false

    func setup() {
        // Detect hardware sample rate before connecting
        let engine = AVAudioEngine()
        let rate = Int(engine.inputNode.outputFormat(forBus: 0).sampleRate)
        sampleRate = rate > 8000 ? rate : 48000
        GhostLog.write("Input sample rate: \(sampleRate)Hz")

        if let key = loadDeepgramKey(), !key.isEmpty {
            deepgramKey = key
            usingDeepgram = true
            GhostLog.write("Deepgram Nova-2 selected")
            requestMicAndConnectDeepgram()
        } else {
            GhostLog.write("No Deepgram key found — falling back to Apple Speech")
            setupAppleSpeech()
        }
    }

    // MARK: - Key loading

    private func loadDeepgramKey() -> String? {
        if let k = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"], !k.isEmpty { return k }
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".deepgram_api_key")
        return try? String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Deepgram path

    private func requestMicAndConnectDeepgram() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                if granted {
                    // Audio capture starts immediately. Any audio sent before the
                    // WebSocket opens is silently dropped by sendToDeepgram.
                    AudioCaptureManager.shared.start()
                    self.connectDeepgram()
                } else {
                    NotificationCenter.default.post(name: .whisperReady, object: nil,
                        userInfo: ["error": "Microphone access denied"])
                }
            }
        }
    }

    private func connectDeepgram() {
        guard !isConnecting else { return }
        isConnecting = true

        // nova-2: best accuracy for conversational speech and technical vocabulary
        // endpointing=400: commit segment after 400ms of silence
        let urlStr = "wss://api.deepgram.com/v1/listen"
            + "?model=nova-2"
            + "&language=en-US"
            + "&smart_format=true"
            + "&interim_results=true"
            + "&endpointing=400"
            + "&encoding=linear16"
            + "&sample_rate=\(sampleRate)"
            + "&channels=1"

        guard let url = URL(string: urlStr) else {
            GhostLog.write("Deepgram: bad URL")
            isConnecting = false
            return
        }

        var req = URLRequest(url: url)
        req.setValue("Token \(deepgramKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        wsSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = wsSession?.webSocketTask(with: req)
        webSocketTask?.resume()
        isConnecting = false

        GhostLog.write("Deepgram WebSocket initiated — awaiting open confirmation")
        startKeepalive()
        receiveLoop()
    }

    private func startKeepalive() {
        keepaliveTimer?.invalidate()
        // Deepgram closes idle connections after ~10s; send KeepAlive every 8s
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.webSocketTask?.send(.string("{\"type\":\"KeepAlive\"}")) { err in
                if let err { GhostLog.write("Keepalive failed: \(err.localizedDescription)") }
            }
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let text) = msg {
                    self.queue.async { self.parseDeepgram(text) }
                }
                self.receiveLoop()

            case .failure(let err):
                GhostLog.write("Deepgram disconnected: \(err.localizedDescription) — reconnecting in 2s")
                self.keepaliveTimer?.invalidate()
                self.keepaliveTimer = nil
                self.webSocketTask = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.connectDeepgram()
                }
            }
        }
    }

    private func parseDeepgram(_ json: String) {
        guard
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let channel = obj["channel"] as? [String: Any],
            let alts = channel["alternatives"] as? [[String: Any]],
            let text = alts.first?["transcript"] as? String,
            !text.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }

        let speechFinal = obj["speech_final"] as? Bool ?? false

        GhostLog.write("Deepgram (\(speechFinal ? "final" : "partial")): \"\(text.suffix(60))\"")

        if speechFinal {
            commitSegment(text)
        } else {
            updatePartial(text)
        }
    }

    // MARK: - Buffer input

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        if usingDeepgram {
            sendToDeepgram(buffer)
        } else {
            queue.async { self.request?.append(buffer) }
        }
    }

    // Called by SystemAudioCapture — sends pre-converted int16 data directly
    func sendSystemAudio(_ data: Data) {
        guard usingDeepgram else { return }
        webSocketTask?.send(.data(data)) { _ in }
    }

    private func sendToDeepgram(_ buffer: AVAudioPCMBuffer) {
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
            GhostLog.write("sendToDeepgram: unsupported buffer format")
            return
        }
        webSocketTask?.send(.data(data)) { err in
            if let err { GhostLog.write("Deepgram send error: \(err.localizedDescription)") }
        }
    }

    // MARK: - Transcript access

    func currentTranscript() -> String {
        queue.sync { (rollingTranscript + " " + currentSegment).trimmingCharacters(in: .whitespaces) }
    }

    func resetTranscript() {
        queue.async { self.rollingTranscript = "" }
        GhostLog.write("Transcript reset")
    }

    // MARK: - Segment management

    private func updatePartial(_ text: String) {
        queue.async {
            self.currentSegment = text
            let full = (self.rollingTranscript + " " + text).trimmingCharacters(in: .whitespaces)
            NotificationCenter.default.post(name: .transcriptUpdate, object: nil, userInfo: ["text": text])
            QuestionDetector.shared.scheduleDetection(transcript: full) { transcript, mode in
                AgentRouter.shared.handle(transcript: transcript, mode: mode)
            }
        }
    }

    private func commitSegment(_ text: String) {
        queue.async {
            GhostLog.write("Commit: \"\(text)\"")
            self.rollingTranscript = String((self.rollingTranscript + " " + text)
                .trimmingCharacters(in: .whitespaces)
                .suffix(self.maxTranscriptLength))
            self.currentSegment = ""
            let full = self.rollingTranscript
            NotificationCenter.default.post(name: .transcriptUpdate, object: nil, userInfo: ["text": text])
            guard !full.isEmpty else { return }
            QuestionDetector.shared.fireIfQuestion(transcript: full) { transcript, mode in
                AgentRouter.shared.handle(transcript: transcript, mode: mode)
            }
        }
    }

    // Snapshot currentSegment from queue — safe to call from any thread
    private func pendingSegment() -> String {
        queue.sync { currentSegment }
    }

    private func clearPendingSegment() {
        queue.async { self.currentSegment = "" }
    }

    // MARK: - Apple Speech fallback

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

        let pending = pendingSegment()
        if !pending.isEmpty { commitSegment(pending) }

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
                    let final = text.isEmpty ? self.pendingSegment() : text
                    if !final.isEmpty { self.commitSegment(final) } else { self.clearPendingSegment() }
                    self.isRestarting = false
                    DispatchQueue.main.async { self.startAppleRecognition() }
                } else {
                    self.updatePartial(text)
                }
            }
            if let err = error as NSError?, err.code != 301 {
                if err.code == 1110 {
                    let p = self.pendingSegment()
                    if !p.isEmpty { self.commitSegment(p) }
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
}

// MARK: - Deepgram WebSocket open confirmation

extension TranscriptionManager: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        GhostLog.write("Deepgram WebSocket opened ✓")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isReady = true
            // Fire whisperReady once per app lifetime — reconnects reuse the open session
            guard !self.hasNotifiedReady else { return }
            self.hasNotifiedReady = true
            NotificationCenter.default.post(name: .whisperReady, object: nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        GhostLog.write("Deepgram WebSocket closed: code=\(closeCode.rawValue)")
    }
}
