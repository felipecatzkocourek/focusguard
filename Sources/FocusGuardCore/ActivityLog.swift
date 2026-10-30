import Foundation

/// Something worth showing in the dashboard's "Today" list.
public struct ActivityEvent: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: Codable, Equatable, Sendable {
        case sessionStarted(focus: String)
        case sessionEnded
        case allowanceGranted(domain: String, reason: String, minutes: Int)
        case allowanceExpired(domain: String)
        case cycleStarted(plan: Plan)
        case activeEnded(planned: TimeInterval, actual: TimeInterval)
        case breakEnded(planned: TimeInterval, actual: TimeInterval)
        case idle(duration: TimeInterval)
        case cycleEnded(PomodoroCycle.Ending)

        /// How long an ended Active ran past its planned length; zero for other kinds.
        /// Derived rather than stored, so it can't drift from the two lengths.
        public var overtime: TimeInterval {
            guard case .activeEnded(let planned, let actual) = self else { return 0 }
            return max(actual - planned, 0)
        }
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

    /// Events in the decoded file that this build couldn't decode (e.g. a kind added by a
    /// newer build). They're reported to unified logging, kept out of `events`, and not
    /// saved back. Not part of the log's identity.
    public private(set) var skipped: [SkippedEvent] = []

    /// The raw form of an event that failed to decode, and why.
    public struct SkippedEvent: Equatable, Sendable {
        public let json: String
        public let error: String
    }

    /// Events older than this are dropped to keep the file small.
    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    public init(events: [ActivityEvent] = []) {
        self.events = events.sorted { $0.date < $1.date }
    }

    private enum CodingKeys: String, CodingKey { case events }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([LossyEvent].self, forKey: .events)
        events = entries.compactMap(\.event)
        skipped = entries.compactMap(\.skipped)
        for event in skipped {
            Log.persistence.error(
                "Skipped an activity event this build can't decode: \(event.json, privacy: .public) — \(event.error, privacy: .public)"
            )
        }
    }

    public static func == (lhs: ActivityLog, rhs: ActivityLog) -> Bool {
        lhs.events == rhs.events
    }

    /// One entry of `events`: decodes as an event when it can, and otherwise keeps its raw
    /// JSON instead of failing the whole log.
    private struct LossyEvent: Decodable {
        var event: ActivityEvent?
        var skipped: SkippedEvent?

        init(from decoder: Decoder) throws {
            do {
                event = try ActivityEvent(from: decoder)
            } catch {
                let json = (try? JSONValue(from: decoder))?.jsonString ?? "<not JSON>"
                skipped = SkippedEvent(json: json, error: String(describing: error))
            }
        }
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
