import Foundation

enum ClueyLog {
    static let path = (NSHomeDirectory() as NSString).appendingPathComponent("cluey-debug.log")

    static func write(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
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
