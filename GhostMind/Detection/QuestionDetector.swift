import Foundation

class QuestionDetector {
    static let shared = QuestionDetector()

    private var debounceTask: Task<Void, Never>?
    private let silenceThreshold: Double = AppConfig.questionDebounceSeconds
    private let cooldownInterval: TimeInterval = AppConfig.answerCooldownSeconds
    private var lastFireTime = Date.distantPast
    private var lastTranscriptLength = 0

    // Question signals — anything resembling a request, prompt, or interrogative.
    // We no longer classify into coding/system-design/conceptual/behavioral; Claude
    // figures out the type itself and shapes the answer accordingly.
    private let questionSignals = [
        "how would you", "how do you", "how do we", "how can you", "how can we",
        "how does", "how would", "how should", "how is", "how are",
        "can you", "could you", "would you", "should i",
        "implement a", "implement the", "design a", "design the", "build a", "build the",
        "write a", "write the", "given a", "find the", "return the",
        "walk me through", "tell me about", "tell me how", "tell me what",
        "what's your approach", "what is your approach",
        "explain how", "explain what", "explain the", "explain this",
        "what would you do", "what is a", "what is an", "what are",
        "what is", "what does", "what do you", "what's the",
        "describe how", "describe the", "describe a",
        "help me", "show me", "give me an example",
        "why do", "why is", "why are", "why would", "why does",
        "when should", "when would", "when do",
        "compare", "difference between"
    ]

    // Returns true if the text looks like an interviewer prompt that warrants an answer.
    func isQuestion(_ transcript: String) -> Bool {
        let lower = transcript.lowercased()
        if lower.hasSuffix("?") || lower.hasSuffix("? ") { return true }
        return questionSignals.contains { lower.contains($0) }
    }

    private func canFire() -> Bool {
        Date().timeIntervalSince(lastFireTime) >= cooldownInterval
    }

    // Called after each committed segment — fires immediately if the committed text is a question.
    // No cooldown here: a finalized utterance is a discrete event from the speech recognizer,
    // and the user expects every new question to refresh the answer.
    func fireIfQuestion(transcript: String, latestUtterance: String, handler: @escaping (String, AssistMode) -> Void) {
        guard isQuestion(latestUtterance) else {
            GhostLog.write("QuestionDetector: no question pattern in latest: \"\(latestUtterance.suffix(60))\"")
            return
        }
        lastFireTime = Date()
        GhostLog.write("QuestionDetector: FIRED (commit) — q=\"\(latestUtterance.suffix(80))\"")
        handler(transcript, .assist)
    }

    // Called on every partial — fires after silence threshold
    func scheduleDetection(transcript: String, onDetected: @escaping (String, AssistMode) -> Void) {
        guard transcript.count != lastTranscriptLength else { return }
        lastTranscriptLength = transcript.count

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(silenceThreshold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self.canFire() else { return }

            GhostLog.write("QuestionDetector: analyzing partial (\(transcript.count) chars): \"\(transcript.suffix(60))\"")
            if self.isQuestion(transcript) {
                self.lastFireTime = Date()
                GhostLog.write("QuestionDetector: FIRED (partial)")
                DispatchQueue.main.async { onDetected(transcript, .assist) }
            } else {
                GhostLog.write("QuestionDetector: no question detected")
            }
        }
    }
}
