# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Fixed
- Firefox ignoring block changes until restarted (#16).
