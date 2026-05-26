import Foundation

class ClaudeClient {
    static let shared = ClaudeClient()

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private lazy var apiKey: String = {
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty { return key }
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".ghostmind_api_key")
        return (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }()

    private var streamTask: Task<Void, Never>?

    func streamAnswer(
        transcript: String,
        mode: AssistMode,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        streamTask?.cancel()

        let key = apiKey
        GhostLog.write("ClaudeClient: mode=\(mode), key=\(key.isEmpty ? "MISSING" : String(key.prefix(8)) + "...")")

        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": AppConfig.claudeModel,
            "max_tokens": AppConfig.maxTokens,
            "stream": true,
            "system": PromptTemplates.systemPrompt(for: mode),
            "messages": [["role": "user", "content": PromptTemplates.userPrompt(transcript: transcript, mode: mode)]]
        ]
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)

        streamTask = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

                if let http = response as? HTTPURLResponse {
                    GhostLog.write("ClaudeClient: HTTP \(http.statusCode)")
                    guard (200..<300).contains(http.statusCode) else {
                        let err = NSError(domain: "ClaudeClient", code: http.statusCode,
                                         userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) — check API key"])
                        DispatchQueue.main.async { onError(err) }
                        return
                    }
                }

                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonStr = String(line.dropFirst(6))
                    guard jsonStr != "[DONE]",
                          let jsonData = jsonStr.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let type = json["type"] as? String else { continue }

                    if type == "content_block_delta",
                       let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        DispatchQueue.main.async { onToken(text) }
                    }
                }

                if !Task.isCancelled {
                    DispatchQueue.main.async { onComplete() }
                }
            } catch {
                if Task.isCancelled { return }
                let nsErr = error as NSError
                if nsErr.code == NSURLErrorCancelled { return }
                if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorNetworkConnectionLost { return }
                GhostLog.write("ClaudeClient: error — \(error.localizedDescription)")
                DispatchQueue.main.async { onError(error) }
            }
        }
    }
}
