import os

/// Core's unified logging, under the app's subsystem. Read it with:
///
///     log show --last 10m --predicate 'subsystem == "com.felipekocourek.focusguard"'
enum Log {
    private static let subsystem = "com.felipekocourek.focusguard"
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
