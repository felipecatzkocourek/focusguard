# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Core library: domain normalization/validation, `/etc/hosts` section editing, block
  planning, activity log, `focusguard://` URL commands, JSON persistence.
- Privileged helper (`focusguard-helper`) with a scoped sudoers install/uninstall script.
- Dashboard window: Work status, time in Work today, per-site state, today's activity.
- Friction-gated temporary unblock (countdown + reason, auto re-block on expiry and quit).
- Lock on removing sites and lowering friction while Work is on.
- Menu bar item, launch at login, Setup tab with helper install and Shortcuts instructions.
- `scripts/build-app.sh` to package `FocusGuard.app`; `scripts/test.sh` that works with only
  the Command Line Tools.
- CI on GitHub Actions; PR and issue templates.
