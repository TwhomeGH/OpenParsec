import Foundation

final class OpenParsecLogger {
    static let shared = OpenParsecLogger()
    private let fileURL: URL
    private let queue = DispatchQueue(label: "openparsec.logger")

    private init() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = tmp.appendingPathComponent("openparsec_logs.txt")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }
    }

    func append(_ msg: String) {
        let line = "\(Date()) - \(msg)\n"
        queue.async {
            if let fh = try? FileHandle(forWritingTo: self.fileURL) {
                fh.seekToEndOfFile()
                if let data = line.data(using: .utf8) { fh.write(data) }
                try? fh.close()
            } else {
                try? line.write(to: self.fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    func read() -> String {
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func clear() {
        queue.async {
            try? "".write(to: self.fileURL, atomically: true, encoding: .utf8)
        }
    }
}
