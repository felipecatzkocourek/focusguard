# FocusGuard

[![CI](https://github.com/felipecatzkocourek/focusguard/actions/workflows/ci.yml/badge.svg)](https://github.com/felipecatzkocourek/focusguard/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**A macOS app that blocks distracting websites while your Work Focus is on — with your
iPhone as the remote.**

Switch to **Work** in Control Center on your iPhone, and a few seconds later Instagram and
YouTube stop loading on your Mac. A dashboard on your second monitor shows that you're in
Work mode, how long you've been focused today, and what's blocked. When you genuinely need
a blocked site (that one YouTube tutorial), you can unlock it for a few minutes, but only
after waiting out a short countdown and writing down why.

> **Status:** v0.1 in development. See the [roadmap](#roadmap).

<!-- TODO: add a screenshot / GIF of the dashboard (docs/screenshot.png) -->

## Features

- **Focus-driven:** blocking follows the macOS/iOS **Work** Focus. Turn it on from your
  iPhone, Mac, Apple Watch, or a schedule; Focus sync does the rest.
- **System-wide blocking:** works in every browser (Safari, Chrome, Firefox, Arc…) because
  it blocks at the DNS level through `/etc/hosts`, including IPv6 and `www.`/`m.` variants.
- **Dashboard for a second monitor:** big status, time in Work today, live per-site state
  and a log of the day. It remembers which screen it lives on.
- **Friction, not a hard wall:** temporarily allow one site for 5, 15 or 30 minutes after a
  countdown (default 60 s) and a typed reason. It re-blocks automatically, even if you
  quit the app.
- **No loosening in the moment:** while Work is on you can add sites but not remove them,
  and friction settings are locked.
- **Plays nicely with others:** only edits its own marked section of `/etc/hosts`; other
  tools' entries are left untouched.

## How it works

```mermaid
flowchart LR
    A["iPhone<br/>Work Focus ON"] -- "Focus sync<br/>(iCloud)" --> B["Mac<br/>Work Focus ON"]
    B -- "Shortcuts automation<br/>Open URL" --> C["FocusGuard.app<br/>focusguard://work/on"]
    C -- "sudo -n" --> D["focusguard-helper<br/>(root)"]
    D -- "rewrites own section" --> E["/etc/hosts"]
    E --> F["instagram.com → 0.0.0.0<br/>youtube.com → 0.0.0.0"]
```

1. **Focus sync.** With *Share Across Devices* on (System Settings → Focus), turning Work
   on or off on any of your devices changes it on the Mac too.
2. **Shortcuts automation.** Two personal automations on the Mac, *When Work turns on* and
   *When Work turns off*, open `focusguard://work/on` and `focusguard://work/off`. Opening
   the URL also launches FocusGuard if it isn't running.
3. **The app** keeps the state (Work on/off, temporary allowances, activity log) and works
   out which hostnames should be blocked right now.
4. **The privileged helper** is the only component that runs as root. It validates every
   hostname and rewrites FocusGuard's section of `/etc/hosts` atomically, then flushes the
   DNS cache.

### Project structure

```
Sources/
  FocusGuardCore/     Pure logic, no UI, fully unit-tested
    Domain.swift        normalize & validate user input → hostnames
    HostsFile.swift     rewrite only FocusGuard's section of /etc/hosts
    BlockState.swift    Work state, temporary allowances, BlockPlanner
    ActivityLog.swift   events + "time in Work today"
    FocusCommand.swift  focusguard://work/on|off
    JSONStore.swift     persistence in ~/Library/Application Support/FocusGuard
  FocusGuardHelper/   Root CLI: block <hosts…> | clear | status
  FocusGuard/         AppKit + SwiftUI app (dashboard, menu bar, URL handling)
Tests/FocusGuardCoreTests/
helper/               install.sh / uninstall.sh for the privileged helper
scripts/              build-app.sh, test.sh
```

The split is deliberate: everything that decides *what* to block lives in
`FocusGuardCore`, where it can be tested without a UI or root. The app and the helper are
thin shells around it.

## Installation

Requirements: macOS 14 Sonoma or later and Swift 6 (the Xcode **Command Line Tools** are
enough; full Xcode is not required).

```bash
git clone https://github.com/felipecatzkocourek/focusguard.git
cd focusguard
./scripts/build-app.sh --install
open ~/Applications/FocusGuard.app
```

Then follow the **Setup** tab in the app:

1. **Install the helper.** Click *Install Helper…* and enter your admin password once.
2. **Create the two Shortcuts automations.** In Shortcuts → Automation → New Automation →
   Focus → Work:
   - *When Turning On* → **Open URLs** → `focusguard://work/on`
   - *When Turning Off* → **Open URLs** → `focusguard://work/off`

   Set both to **Run Immediately**.
3. **Drag the window to your second monitor** and turn on *Open FocusGuard when I log in*
   in Settings.

You can test without Shortcuts:

```bash
open "focusguard://work/on"
```

### Uninstall

```bash
sudo ~/Applications/FocusGuard.app/Contents/Resources/uninstall.sh
rm -rf ~/Applications/FocusGuard.app ~/Library/Application\ Support/FocusGuard
```

`uninstall.sh` removes the helper and its sudoers rule and clears FocusGuard's section of
`/etc/hosts`, so nothing stays blocked.

## Security

Editing `/etc/hosts` needs root, and a productivity app should not get blanket admin
rights. FocusGuard keeps the privileged part as small and auditable as possible:

| Concern | How it's handled |
| --- | --- |
| What runs as root | Only `focusguard-helper` (~120 lines). The app itself never runs as root. |
| Who can replace the helper | It's installed in `/Library/PrivilegedHelperTools`, owned by `root:wheel`, mode `755`. A normal user can't modify it. |
| Password-less sudo scope | `/etc/sudoers.d/focusguard` allows **only that one binary** for **only your user**. The rule is checked with `visudo -cf` before it's installed. |
| Injection into `/etc/hosts` | Every argument must pass a strict RFC 1123 hostname check. Newlines, spaces, IPs and anything else are rejected before the file is touched. |
| Damaging the hosts file | Only lines between `# BEGIN FocusGuard` and `# END FocusGuard` are ever rewritten. Writes are atomic (temp file + `rename`), so a crash can't leave a half-written file. |

The worst a compromised user account can do with the helper is block or unblock websites.

## Limitations

- **This is a commitment device, not parental controls.** An admin user can always undo
  it (edit `/etc/hosts`, uninstall the helper). The point is to break the reflex, not to
  be unbreakable.
- **Browsers cache DNS.** A tab that's already open may keep working for up to about a
  minute after blocking starts. The helper flushes the system cache, but Chrome keeps its
  own.
- **No wildcard subdomains.** `/etc/hosts` can't express `*.youtube.com`; FocusGuard
  blocks the bare domain plus `www.` and `m.`.
- **DNS-over-HTTPS** set to a custom provider in a browser can bypass `/etc/hosts`.
- **The Mac must be awake** for the automation to run. FocusGuard re-applies its saved state on
  wake ([#8](https://github.com/felipecatzkocourek/focusguard/issues/8) tracks reading the
  actual Focus on launch).

## Development

```bash
./scripts/test.sh          # unit tests (Swift Testing)
swift build                # debug build of everything
./scripts/build-app.sh     # build/FocusGuard.app
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branching model, commit conventions and
release process.

## Roadmap

Tracked in [milestones](https://github.com/felipecatzkocourek/focusguard/milestones):

- **v0.1.0:** Focus-triggered blocking, dashboard, friction-gated temporary unblocks
- **v0.2.0:** Pomodoro timer on the dashboard ([#6](https://github.com/felipecatzkocourek/focusguard/issues/6))
- **Backlog:** verify iPhone→Mac Focus sync triggers automations, read the real Focus
  state on launch, a custom "you're in Work mode" page, an app icon

## Tech stack

Swift 6 (strict concurrency) · SwiftUI + AppKit · Swift Package Manager · Swift Testing ·
Observation · ServiceManagement · Shortcuts · GitHub Actions

## License

[MIT](LICENSE) © 2026 Felipe Kocourek
