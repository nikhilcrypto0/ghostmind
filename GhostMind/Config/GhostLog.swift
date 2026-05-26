import Foundation

enum GhostLog {
    static let path = (NSHomeDirectory() as NSString).appendingPathComponent("ghostmind-debug.log")
    private static let queue = DispatchQueue(label: "com.ghostmind.log", qos: .utility)

    static func write(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: path),
               let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
