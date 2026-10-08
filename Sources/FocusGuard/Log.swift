import os

/// Unified logging. Read it with:
///
///     log show --last 10m --predicate 'subsystem == "com.felipekocourek.focusguard"'
enum Log {
    private static let subsystem = "com.felipekocourek.focusguard"
    static let session = Logger(subsystem: subsystem, category: "session")
    static let hosts = Logger(subsystem: subsystem, category: "hosts")
    static let browsers = Logger(subsystem: subsystem, category: "browsers")
}
