import Foundation

enum GhostLog {
    static let path = (NSHomeDirectory() as NSString).appendingPathComponent("ghostmind-debug.log")
    private static let queue = DispatchQueue(label: "com.ghostmind.log", qos: .utility)

    // Lazy-initialized persistent handle so high-frequency log calls don't
    // open/seek/close a FileHandle on every line. Mutated only on `queue`.
    nonisolated(unsafe) private static var handle: FileHandle? = {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let fh = FileHandle(forWritingAtPath: path) else { return nil }
        _ = try? fh.seekToEnd()
        return fh
    }()

    static func write(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let fh = handle {
                try? fh.write(contentsOf: data)
            } else {
                // Cold path — handle init failed once; retry via one-shot write.
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
    }
}
