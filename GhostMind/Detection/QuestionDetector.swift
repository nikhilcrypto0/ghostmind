import Foundation
import SwiftUI

enum QuestionType {
    case coding, systemDesign, conceptual, behavioral

    var label: String {
        switch self {
        case .coding:       return "Coding"
        case .systemDesign: return "System Design"
        case .conceptual:   return "Conceptual"
        case .behavioral:   return "Behavioral"
        }
    }

    var color: Color {
        switch self {
        case .coding:       return .blue
        case .systemDesign: return .orange
        case .conceptual:   return .teal
        case .behavioral:   return .green
        }
    }
}

class QuestionDetector {
    static let shared = QuestionDetector()

    private var debounceTask: Task<Void, Never>?
    private let silenceThreshold: Double = 1.5
    private let cooldownInterval: TimeInterval = 5.0
    private var lastFireTime = Date.distantPast
    private var lastTranscriptLength = 0

    private let codingSignals = [
        "implement", "write a function", "write code", "algorithm", "complexity",
        "binary", "tree", "graph", "array", "string", "dynamic programming",
        "recursion", "iteration", "sort", "search", "hash", "linked list",
        "stack", "queue", "heap", "trie", "backtracking", "leetcode",
        "big o", "time complexity", "space complexity", "optimize", "brute force"
    ]

    private let designSignals = [
        "design a system", "design the", "scale", "architecture", "microservice",
        "load balancer", "cdn", "distributed", "consistency", "availability",
        "throughput", "latency", "sharding", "replication", "message queue",
        "rate limiting", "event driven", "service mesh", "data pipeline"
    ]

    private let conceptualSignals = [
        "what is", "what are", "what does", "what do you mean",
        "what's the difference", "difference between", "compare",
        "explain", "define", "definition of",
        "how does", "how do", "how would you describe",
        "what happens when", "why do we", "why is", "why are",
        "what is the purpose", "what is the benefit", "what is the advantage",
        "when should", "when would you use", "when do you",
        "what problem does", "what problem do", "what is meant by",
        "describe what", "tell me what", "tell me how"
    ]

    private let questionSignals = [
        "how would you", "how do you", "how do we", "how can you", "how can we",
        "how does", "how would", "how should",
        "can you", "could you", "would you",
        "implement a", "implement the", "design a", "design the",
        "write a", "write the", "given a", "find the", "return the",
        "walk me through", "tell me about", "tell me how",
        "what's your approach", "what is your approach",
        "explain how", "explain what", "explain the",
        "what would you do", "what is a", "what is an", "what are",
        "describe how", "describe the", "describe a",
        "help me", "show me", "give me an example",
        "what do you know about", "can you explain",
        "what is the", "how does", "why do", "why is", "what happens"
    ]

    func analyze(transcript: String) -> (isQuestion: Bool, type: QuestionType)? {
        let lower = transcript.lowercased()
        let endsWithQuestion = lower.hasSuffix("?") || lower.hasSuffix("? ")
        let hasQuestionSignal = questionSignals.contains { lower.contains($0) }

        guard endsWithQuestion || hasQuestionSignal else { return nil }
        return (true, classify(lower))
    }

    private func classify(_ text: String) -> QuestionType {
        let codingScore = codingSignals.filter { text.contains($0) }.count
        let designScore = designSignals.filter { text.contains($0) }.count
        let conceptualScore = conceptualSignals.filter { text.contains($0) }.count

        // Strong technical signal wins
        if codingScore >= 2 { return .coding }
        if designScore >= 2 { return .systemDesign }
        if codingScore > 0 && codingScore > designScore { return .coding }
        if designScore > 0 && designScore > codingScore { return .systemDesign }

        // Knowledge/definition questions (e.g. "What are AI agents?")
        if conceptualScore >= 1 { return .conceptual }

        // Story-based behavioral (tell me about a time, describe a situation)
        return .behavioral
    }

    private func canFire() -> Bool {
        Date().timeIntervalSince(lastFireTime) >= cooldownInterval
    }

    // Called after each committed segment — fires immediately if transcript is a question
    func fireIfQuestion(transcript: String, handler: @escaping (String, AssistMode) -> Void) {
        guard canFire() else { return }
        guard let result = analyze(transcript: transcript) else {
            GhostLog.write("QuestionDetector: no question pattern in \"\(transcript.suffix(60))\"")
            return
        }
        lastFireTime = Date()
        GhostLog.write("QuestionDetector: FIRED (commit) — type=\(result.type)")
        handler(transcript, .assist(result.type))
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
            if let result = self.analyze(transcript: transcript) {
                self.lastFireTime = Date()
                GhostLog.write("QuestionDetector: FIRED (partial) — type=\(result.type)")
                DispatchQueue.main.async { onDetected(transcript, .assist(result.type)) }
            } else {
                GhostLog.write("QuestionDetector: no question detected")
            }
        }
    }
}
