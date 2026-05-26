import Foundation

protocol DeepgramStreamDelegate: AnyObject {
    func deepgramStream(_ stream: DeepgramStream, didProducePartial text: String)
    func deepgramStream(_ stream: DeepgramStream, didCommitSegment text: String)
    func deepgramStreamDidOpen(_ stream: DeepgramStream)
}

// One Deepgram Nova-2 WebSocket connection. Either represents the candidate
// (mic) or the interviewer (system audio). Owns its own keepalive,
// receive-loop, and reconnect logic.
final class DeepgramStream: NSObject {
    enum Source: String {
        case mic = "You"
        case system = "Interviewer"
    }

    let source: Source
    weak var delegate: DeepgramStreamDelegate?

    private let apiKey: String
    private let sampleRate: Int
    private let parseQueue: DispatchQueue
    private let stateQueue: DispatchQueue

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var keepaliveTimer: Timer?
    private var isConnecting = false
    private var hasNotifiedOpen = false

    // Transcript state (accessed only via stateQueue)
    private var _transcript = ""
    private var _currentSegment = ""
    private var _lastUtterance = ""

    init(source: Source, apiKey: String, sampleRate: Int) {
        self.source = source
        self.apiKey = apiKey
        self.sampleRate = sampleRate
        self.parseQueue = DispatchQueue(label: "com.ghostmind.deepgram.\(source.rawValue).parse", qos: .userInitiated)
        self.stateQueue = DispatchQueue(label: "com.ghostmind.deepgram.\(source.rawValue).state")
        super.init()
    }

    var transcript: String { stateQueue.sync { _transcript } }
    var currentSegment: String { stateQueue.sync { _currentSegment } }
    var lastUtterance: String { stateQueue.sync { _lastUtterance } }

    func connect() {
        guard !isConnecting else { return }
        isConnecting = true

        // Always tear down any previous session before creating a new one —
        // reconnect paths must not leak URLSessions or their retained delegates.
        session?.invalidateAndCancel()
        session = nil

        let urlStr = "wss://api.deepgram.com/v1/listen"
            + "?model=\(AppConfig.deepgramModel)"
            + "&language=en-US"
            + "&smart_format=true"
            + "&interim_results=true"
            + "&endpointing=400"
            + "&encoding=linear16"
            + "&sample_rate=\(sampleRate)"
            + "&channels=1"

        guard let url = URL(string: urlStr) else {
            GhostLog.write("Deepgram(\(source.rawValue)): bad URL")
            isConnecting = false
            return
        }

        var req = URLRequest(url: url)
        req.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session?.webSocketTask(with: req)
        webSocketTask?.resume()
        // NOTE: do NOT clear isConnecting here — the handshake hasn't completed.
        // It's cleared in didOpenWithProtocol (success) or disconnect() (teardown).

        GhostLog.write("Deepgram(\(source.rawValue)) WebSocket initiated")
        startKeepalive()
        receiveLoop()
    }

    func send(_ data: Data) {
        webSocketTask?.send(.data(data)) { [weak self] err in
            if let err {
                GhostLog.write("Deepgram(\(self?.source.rawValue ?? "?")) send error: \(err.localizedDescription)")
            }
        }
    }

    func disconnect() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        isConnecting = false
        hasNotifiedOpen = false
    }

    private func startKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.webSocketTask?.send(.string("{\"type\":\"KeepAlive\"}")) { _ in }
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let text) = msg {
                    self.parseQueue.async { self.parse(text) }
                }
                self.receiveLoop()
            case .failure(let err):
                GhostLog.write("Deepgram(\(self.source.rawValue)) disconnected: \(err.localizedDescription) — reconnecting in 2s")
                // Tear down everything before scheduling the reconnect so connect()
                // starts from a clean slate (no leaked URLSession, flags reset).
                self.keepaliveTimer?.invalidate()
                self.keepaliveTimer = nil
                self.webSocketTask = nil
                self.session?.invalidateAndCancel()
                self.session = nil
                self.isConnecting = false
                self.hasNotifiedOpen = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.connect()
                }
            }
        }
    }

    private func parse(_ json: String) {
        guard
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let channel = obj["channel"] as? [String: Any],
            let alts = channel["alternatives"] as? [[String: Any]],
            let text = alts.first?["transcript"] as? String,
            !text.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }

        let speechFinal = obj["speech_final"] as? Bool ?? false
        GhostLog.write("Deepgram(\(source.rawValue)) \(speechFinal ? "final" : "partial"): \"\(text.suffix(60))\"")

        if speechFinal {
            stateQueue.sync {
                _transcript = String((_transcript + " " + text)
                    .trimmingCharacters(in: .whitespaces)
                    .suffix(AppConfig.maxTranscriptLength))
                _currentSegment = ""
                _lastUtterance = text
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.deepgramStream(self, didCommitSegment: text)
            }
        } else {
            stateQueue.sync { _currentSegment = text }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.deepgramStream(self, didProducePartial: text)
            }
        }
    }
}

extension DeepgramStream: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        GhostLog.write("Deepgram(\(source.rawValue)) WebSocket opened ✓")
        isConnecting = false
        guard !hasNotifiedOpen else { return }
        hasNotifiedOpen = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.deepgramStreamDidOpen(self)
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        GhostLog.write("Deepgram(\(source.rawValue)) WebSocket closed: code=\(closeCode.rawValue)")
    }
}
