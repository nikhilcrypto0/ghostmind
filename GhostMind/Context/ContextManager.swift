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

    private static let jobDescriptionLimit = 800
    private static let resumeLimit = 600

    var contextBlock: String {
        var parts: [String] = []
        if !jobDescription.isEmpty {
            if jobDescription.count > Self.jobDescriptionLimit {
                GhostLog.write("ContextManager: job description truncated \(jobDescription.count)→\(Self.jobDescriptionLimit) chars")
            }
            parts.append("Job Description:\n\(jobDescription.prefix(Self.jobDescriptionLimit))")
        }
        if !resumeSummary.isEmpty {
            if resumeSummary.count > Self.resumeLimit {
                GhostLog.write("ContextManager: resume truncated \(resumeSummary.count)→\(Self.resumeLimit) chars")
            }
            parts.append("Candidate Background:\n\(resumeSummary.prefix(Self.resumeLimit))")
        }
        guard !parts.isEmpty else { return "" }
        return "\n\n---\n" + parts.joined(separator: "\n\n") + "\n---"
    }
}
