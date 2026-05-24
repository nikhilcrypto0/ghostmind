import Foundation

enum AppConfig {
    static var anthropicAPIKey: String {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    static let whisperModel = "base.en"
    static let claudeModel = "claude-haiku-4-5"
    static let maxTokens = 1024
    static let audioChunkInterval: TimeInterval = 5.0
    static let questionDebounceSeconds: Double = 2.0
    static let answerCooldownSeconds: Double = 8.0
    static let maxTranscriptLength = 2000
    static let hudWidth: CGFloat = 420
    static let hudMaxHeight: CGFloat = 600
    static let hudMargin: CGFloat = 20
}
