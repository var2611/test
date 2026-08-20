import Foundation
import OSLog

/// Category-separated loggers. Nothing user-identifying is ever logged: the app
/// has no account, no analytics and no network calls of its own, and the log
/// statements keep that promise by staying at the level of states and errors.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.wattson.app"

    static let power = Logger(subsystem: subsystem, category: "power")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
