import Foundation

enum AppConfig {
    static var anthropicAPIKey: String {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    // Claude
    static let claudeModel = "claude-haiku-4-5-20251001"
    static let maxTokens = 1024

    // Deepgram
    static let deepgramModel = "nova-3"

    // Transcript
    static let maxTranscriptLength = 8000

    // QuestionDetector
    static let questionDebounceSeconds: Double = 1.5
    static let answerCooldownSeconds: TimeInterval = 5.0

    // HUD
    static let hudWidth: CGFloat = 480
    static let hudHeight: CGFloat = 620
    static let hudMargin: CGFloat = 20
}
