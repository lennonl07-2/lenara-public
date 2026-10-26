import Foundation

// MARK: - Logger
struct AppLogger {
    static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        print("[Lenara] \(fileName):\(line) \(function) - \(message)")
        #endif
    }

    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        print("[Lenara ERROR] \(fileName):\(line) \(function) - \(message)", terminator: "")
    }
}
