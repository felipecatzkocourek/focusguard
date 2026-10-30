# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Pomodoro tab: build a Plan by hand (Active length, Break length, number of Actives) and
  run a Planned Cycle on a large timer. Actives run into Overtime until you end them, Breaks
  end on their own, and the Cycle waits in Idle until you start the next Active. Every Phase
  and each Cycle's start and end appear in today's activity. The Cycle doesn't block anything
  yet.
- Cutting a Pomodoro Active short: ending it, stopping or quitting the app before its
  planned length shows the time left and asks for a typed reason. The Active is logged as cut
  short with its Shortfall and the reason. A Break can be ended early without a reason; it is
  logged as cut short and the next Active starts right away. Quitting at any other point ends
  the Cycle without asking ("app quit"); a shutdown or logout never asks, and a Cycle left open
  by a crash or force quit is closed at the next launch, both logged as ended by the system.

### Fixed
- An activity event this build can't decode (e.g. a kind written by a newer build) no
  longer wipes the whole activity history: it's skipped, reported to unified logging
  (category `persistence`) and left out of the next save, and every other event is kept.
- A store file (`config.json`, `state.json`, `activity.json`) that exists but can't be
  decoded is moved aside to `<name>.unreadable-<timestamp>` and logged before FocusGuard
  falls back to defaults, so the next save no longer overwrites it.
- `scripts/build-app.sh` no longer aborts with "unbound variable" under macOS's bash 3.2
  before assembling the app bundle.

## [0.1.0] - 2026-10-08

### Added
- Core library: domain normalization/validation, `/etc/hosts` section editing, block
  planning, activity log, JSON persistence.
- Focus detection: FocusGuard reads the macOS Focus database (Full Disk Access) and blocks
  while any of the user's chosen Focus modes is on. A failed read keeps the current state.
- Self-healing: manual edits to FocusGuard's `/etc/hosts` section are reverted during a
  session.
- Privileged helper (`focusguard-helper`) with a scoped sudoers install/uninstall script.
- Dashboard window: blocking status, time blocked today, per-site state, today's activity.
- Friction-gated temporary unblock (countdown + reason, auto re-block on expiry and quit).
- Lock on removing sites, trigger modes and lowering friction while blocking is on.
- Menu bar item, launch at login, Setup tab (helper install, Full Disk Access, trigger modes).
- `scripts/build-app.sh` to package `FocusGuard.app`; `scripts/test.sh` that works with only
  the Command Line Tools.
- CI on GitHub Actions; PR and issue templates.
- Close open tabs of newly blocked sites in Safari and Chrome; offer to restart Firefox when
  its saved session shows a blocked site open.
- Optional Firefox policy that disables Firefox's DNS cache, so blocking and unblocking
  take effect immediately (installed from Setup, removed by `uninstall.sh`).

- Blocked sites are kept in Firefox's DNS-over-HTTPS exceptions (via the helper), so
  blocking works with DNS over HTTPS on. The helper reports an API level, and the app asks
  to update an outdated helper.

- `scripts/create-signing-identity.sh`: a stable local code-signing identity, so
  permissions survive rebuilds; `build-app.sh` uses it when present.
- Diagnostics in the unified log for sessions, hosts and Firefox session parsing.

- Restart Firefox automatically when blocking starts (only when it restores its tabs;
  otherwise ask), with a toggle in Settings.

### Fixed
- Firefox ignoring block changes until restarted (#16).

[Unreleased]: https://github.com/felipecatzkocourek/focusguard/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/felipecatzkocourek/focusguard/releases/tag/v0.1.0
