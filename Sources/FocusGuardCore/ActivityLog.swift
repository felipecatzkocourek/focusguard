import Foundation

/// Something worth showing in the dashboard's "Today" list.
public struct ActivityEvent: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: Codable, Equatable, Sendable {
        case sessionStarted(focus: String)
        case sessionEnded
        case allowanceGranted(domain: String, reason: String, minutes: Int)
        case allowanceExpired(domain: String)
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind

    public init(id: UUID = UUID(), date: Date, kind: Kind) {
        self.id = id
        self.date = date
        self.kind = kind
    }
}

public struct ActivityLog: Codable, Equatable, Sendable {
    public private(set) var events: [ActivityEvent]

    /// Events older than this are dropped to keep the file small.
    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    public init(events: [ActivityEvent] = []) {
        self.events = events.sorted { $0.date < $1.date }
    }

    public mutating func record(_ kind: ActivityEvent.Kind, at date: Date) {
        events.append(ActivityEvent(date: date, kind: kind))
        events.removeAll { date.timeIntervalSince($0.date) > Self.retention }
    }

    public func events(on day: Date, calendar: Calendar = .current) -> [ActivityEvent] {
        events.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// Total time blocking was active during the calendar day containing `now`, counting an
    /// ongoing session up to `now`. Sessions that cross midnight are clipped to the day.
    public func blockingDuration(onDayOf now: Date, calendar: Calendar = .current) -> TimeInterval {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        var total: TimeInterval = 0
        var sessionStart: Date?

        func close(at end: Date) {
            guard let start = sessionStart else { return }
            let clippedStart = max(start, dayStart)
            let clippedEnd = min(end, dayEnd)
            if clippedEnd > clippedStart { total += clippedEnd.timeIntervalSince(clippedStart) }
            sessionStart = nil
        }

        for event in events where event.date <= now {
            switch event.kind {
            case .sessionStarted where sessionStart == nil:
                sessionStart = event.date
            case .sessionEnded:
                close(at: event.date)
            default:
                break
            }
        }
        close(at: now)
        return total
    }
}
