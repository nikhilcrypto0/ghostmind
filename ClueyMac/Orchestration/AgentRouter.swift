import Foundation

class AgentRouter {
    static let shared = AgentRouter()

    func handle(transcript: String, mode: AssistMode) {
        ClueyLog.write("AgentRouter: mode=\(mode), transcript=\(transcript.suffix(60))")

        NotificationCenter.default.post(name: .newAnswer, object: nil,
            userInfo: ["question": String(transcript.suffix(120))])

        ClaudeClient.shared.streamAnswer(
            transcript: transcript,
            mode: mode,
            onToken: { token in
                NotificationCenter.default.post(name: .answerToken, object: nil, userInfo: ["token": token])
            },
            onComplete: {
                NotificationCenter.default.post(name: .answerDone, object: nil)
            },
            onError: { error in
                NotificationCenter.default.post(name: .answerToken, object: nil,
                    userInfo: ["token": "\n\n[Error: \(error.localizedDescription)]"])
                NotificationCenter.default.post(name: .answerDone, object: nil)
            }
        )
    }
}
