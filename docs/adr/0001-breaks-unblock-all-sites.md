# 0001. Pomodoro Breaks unblock all sites during a Session

**Status:** accepted

## Context

Until v0.1.0, blocking ends only when the Trigger mode Focus turns off; no control inside the app can lift it, and the only loosening is a single-site Allowance gated by Friction. The Pomodoro timer (#6) introduces Breaks, and the user wants rest periods to give real access to Blocked sites without having to switch the Focus off and on.

## Decision

While a Session is running, a Break makes every Blocked site reachable until the Break ends. The Break ends on its own at its planned length, sites are blocked again and their open tabs are closed, exactly as when blocking starts. This applies even when the Focus is turned on during a Break: nothing is blocked until that Break ends.

The Pomodoro Cycle never blocks sites by itself. Without a Session it is only a timer.

The safeguard moves to the Active: ending an Active before its planned length requires a typed reason, and every Phase (planned and actual length, Overtime, Shortfall, reason) is logged.

## Alternatives discarded

- **Breaks keep blocking; use an Allowance if needed.** Preserves the v0.1.0 guarantee but makes Breaks pointless for the intended use (watching a video while resting).
- **A separate list of "Break sites".** Adds configuration and a second site list for little gain over unblocking everything for a bounded time.
- **The Pomodoro Cycle as a second source of blocking.** Would require redefining the Session around two triggers; the Focus remains the only thing that turns blocking on.

## Consequences

- The README promise "blocking only ends when the Focus really turns off" no longer holds unconditionally and must be reworded: an app control (starting a Break) can now open all sites for a bounded time.
- Ending an Active early is the shortest path to unblocking, so it carries Friction (a reason) and is logged as cut short.
- Pomodoro durations cannot be changed while a Cycle is running. The only way to lengthen a running Break is a Snooze: 5 minutes at a time, at most 6 per Break, each one logged.
- `BlockPlanner` must take the Pomodoro state into account alongside Allowances.
