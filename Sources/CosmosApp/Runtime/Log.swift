import Darwin
import Foundation
import os

struct Log {
    enum Level: String {
        case trace
        case debug
        case info
        case warning
        case error

        var colorCode: String {
            switch self {
            case .trace:
                "\u{001B}[90m"
            case .debug:
                "\u{001B}[36m"
            case .info:
                "\u{001B}[0m"
            case .warning:
                "\u{001B}[33m"
            case .error:
                "\u{001B}[31m"
            }
        }
    }

    private static let subsystem = "dev.cosmos"

    private let category: String
    private let osLogger: Logger

    init(category: String) {
        self.category = category
        osLogger = Logger(subsystem: Self.subsystem, category: category)
    }

    func trace(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        write(.trace, message(), file: file, line: line)
    }

    func debug(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        write(.debug, message(), file: file, line: line)
    }

    func info(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        write(.info, message(), file: file, line: line)
    }

    func warning(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        write(.warning, message(), file: file, line: line)
    }

    func error(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        write(.error, message(), file: file, line: line)
    }

    private func write(
        _ level: Level,
        _ message: String,
        file: StaticString,
        line: UInt
    ) {
        switch level {
        case .trace:
            osLogger.trace("\(message, privacy: .public)")
        case .debug:
            osLogger.debug("\(message, privacy: .public)")
        case .info:
            osLogger.info("\(message, privacy: .public)")
        case .warning:
            osLogger.warning("\(message, privacy: .public)")
        case .error:
            osLogger.error("\(message, privacy: .public)")
        }

        TerminalLogWriter.write(level: level, category: category, message: message, file: file, line: line)
    }
}

private enum TerminalLogWriter {
    private static let resetColor = "\u{001B}[0m"
    private static let processName = ProcessInfo.processInfo.processName
    private static let pid = getpid()
    private static let lock = NSLock()

    static func write(
        level: Log.Level,
        category: String,
        message: String,
        file: StaticString,
        line: UInt
    ) {
        let prefix = [
            timestamp(),
            "\(processName)[\(pid):\(threadID())]",
            "[cosmos \(category)]",
            level.rawValue.uppercased(),
            "\(fileName(file)):\(line)"
        ].joined(separator: " ")
        let output = "\(level.colorCode)\(prefix) \(message)\(resetColor)\n"

        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardError.write(Data(output.utf8))
    }

    private static func timestamp() -> String {
        var now = timeval()
        gettimeofday(&now, nil)

        var seconds = time_t(now.tv_sec)
        var localTime = tm()
        localtime_r(&seconds, &localTime)

        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d.%03d",
            Int(localTime.tm_year) + 1900,
            Int(localTime.tm_mon) + 1,
            Int(localTime.tm_mday),
            Int(localTime.tm_hour),
            Int(localTime.tm_min),
            Int(localTime.tm_sec),
            Int(now.tv_usec) / 1000
        )
    }

    private static func threadID() -> UInt64 {
        var id: UInt64 = 0
        pthread_threadid_np(nil, &id)
        return id
    }

    private static func fileName(_ file: StaticString) -> String {
        let fileID = String(describing: file)
        return fileID.split(separator: "/").last.map(String.init) ?? fileID
    }
}
