import Foundation

class ContextManager {
    static let shared = ContextManager()

    private let defaults = UserDefaults.standard

    var jobDescription: String {
        get { defaults.string(forKey: "jobDescription") ?? "" }
        set { defaults.set(newValue, forKey: "jobDescription") }
    }

    var resumeSummary: String {
        get { defaults.string(forKey: "resumeSummary") ?? "" }
        set { defaults.set(newValue, forKey: "resumeSummary") }
    }

    var captureSystemAudio: Bool {
        get { defaults.object(forKey: "captureSystemAudio") as? Bool ?? true } // on by default
        set { defaults.set(newValue, forKey: "captureSystemAudio") }
    }

    var contextBlock: String {
        var parts: [String] = []
        if !jobDescription.isEmpty {
            parts.append("Job Description:\n\(jobDescription.prefix(800))")
        }
        if !resumeSummary.isEmpty {
            parts.append("Candidate Background:\n\(resumeSummary.prefix(600))")
        }
        guard !parts.isEmpty else { return "" }
        return "\n\n---\n" + parts.joined(separator: "\n\n") + "\n---"
    }
}
