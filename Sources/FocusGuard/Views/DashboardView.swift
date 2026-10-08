import FocusGuardCore
import SwiftUI

enum DashboardTab: Hashable {
    case today, sites, settings, setup
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: DashboardTab = .today

    var body: some View {
        VStack(spacing: 0) {
            if let banner = bannerMessage {
                Banner(message: banner.text, actionTitle: banner.showSetup ? "Open Setup" : nil) { tab = .setup }
            }
            TabView(selection: $tab) {
                TodayView(openSetup: { tab = .setup })
                    .tabItem { Text("Today") }.tag(DashboardTab.today)
                SitesView()
                    .tabItem { Text("Sites") }.tag(DashboardTab.sites)
                SettingsView()
                    .tabItem { Text("Settings") }.tag(DashboardTab.settings)
                SetupView()
                    .tabItem { Text("Setup") }.tag(DashboardTab.setup)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    private var bannerMessage: (text: String, showSetup: Bool)? {
        if model.focus.access == .needsFullDiskAccess && tab != .setup {
            return ("FocusGuard needs Full Disk Access to see which Focus is on.", true)
        }
        if case .unreadable(let reason) = model.focus.access {
            return (reason, false)
        }
        if model.helperStatus == .notInstalled && tab != .setup {
            return ("The helper isn't installed, so sites can't be blocked yet.", true)
        }
        if let error = model.lastError {
            return (error, false)
        }
        return nil
    }
}

private struct Banner: View {
    let message: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let actionTitle { Button(actionTitle, action: action) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }
}

// MARK: - Today

struct TodayView: View {
    @Environment(AppModel.self) private var model
    let openSetup: () -> Void
    @State private var showingAllowSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusCard()
                sitesSection
                activitySection
            }
            .padding(4)
        }
        .sheet(isPresented: $showingAllowSheet) { AllowSheet() }
    }

    private var sitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Blocked sites")
                Spacer()
                Button("Temporarily allow…") { showingAllowSheet = true }
                    .disabled(!model.isBlocking || model.configuration.blockedDomains.isEmpty)
                    .help(model.isBlocking ? "Unblock one site for a few minutes" : "Only needed while blocking is on")
            }
            GroupBox {
                if model.configuration.blockedDomains.isEmpty {
                    Text("No sites yet. Add some in the Sites tab.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 6) {
                            ForEach(model.configuration.blockedDomains, id: \.self) { domain in
                                SiteRow(domain: domain, now: context.date)
                            }
                        }
                        .padding(4)
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Today")
            GroupBox {
                let events = model.log.events(on: .now).reversed()
                if events.isEmpty {
                    Text("Nothing yet today.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(events)) { event in
                            ActivityRow(event: event)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }
        }
    }
}

private struct StatusCard: View {
    @Environment(AppModel.self) private var model

    private var idleHint: String {
        let names = model.triggerModeNames
        if names.isEmpty { return "Pick which Focus modes block sites in Settings." }
        return "Turn on \(ListFormatter.localizedString(byJoining: names)) to start blocking."
    }

    var body: some View {
        let active = model.isBlocking
        HStack(spacing: 16) {
            Image(systemName: active ? "shield.lefthalf.filled" : "shield")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(active ? "\(model.sessionFocusName ?? "Focus") · Blocking on" : "Off")
                    .font(.system(size: 26, weight: .bold))
                Text(active
                     ? "Turn off the \(model.sessionFocusName ?? "") Focus on your iPhone or Mac to stop blocking."
                     : idleHint)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label("\(formatDuration(model.log.blockingDuration(onDayOf: context.date))) blocked today", systemImage: "clock")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(active ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        )
    }
}

private struct SiteRow: View {
    @Environment(AppModel.self) private var model
    let domain: String
    let now: Date

    var body: some View {
        HStack {
            Text(domain).font(.body.monospaced())
            Spacer()
            pill
        }
    }

    @ViewBuilder private var pill: some View {
        if !model.isBlocking {
            StatusPill(text: "Not blocked", color: .secondary)
        } else if let allowance = model.state.allowance(for: domain, at: now) {
            StatusPill(text: "Allowed · \(formatCountdown(allowance.expires.timeIntervalSince(now))) left", color: .orange)
        } else {
            StatusPill(text: "Blocked", color: .red)
        }
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.date, format: .dateTime.hour().minute())
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Image(systemName: icon).foregroundStyle(color).frame(width: 16)
            Text(description).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var icon: String {
        switch event.kind {
        case .sessionStarted: "play.fill"
        case .sessionEnded: "stop.fill"
        case .allowanceGranted: "lock.open.fill"
        case .allowanceExpired: "lock.fill"
        }
    }

    private var color: Color {
        switch event.kind {
        case .sessionStarted: .green
        case .sessionEnded: .secondary
        case .allowanceGranted: .orange
        case .allowanceExpired: .red
        }
    }

    private var description: String {
        switch event.kind {
        case .sessionStarted(let focus): "\(focus) on · blocking started"
        case .sessionEnded: "Blocking ended"
        case .allowanceGranted(let domain, let reason, let minutes):
            reason.isEmpty ? "Allowed \(domain) for \(minutes) min" : "Allowed \(domain) for \(minutes) min: “\(reason)”"
        case .allowanceExpired(let domain): "\(domain) blocked again"
        }
    }
}

// MARK: - Shared bits

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.headline) }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let minutes = Int(interval) / 60
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}

func formatCountdown(_ interval: TimeInterval) -> String {
    let seconds = max(Int(interval.rounded(.up)), 0)
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}
