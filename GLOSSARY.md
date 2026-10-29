# FocusGuard

A macOS commitment device that blocks distracting websites while the user is focused, and makes loosening the block deliberate instead of reflexive.

## Language

### Blocking

**Blocked site**:
A domain the user has chosen to make unreachable while blocking is on.
_Avoid_: Blocked app, distraction

**Trigger mode**:
A system Focus mode that, while on, turns blocking on.
_Avoid_: Work mode (when meaning the setting rather than Apple's Work Focus)

**Session**:
The span during which a Trigger mode is on and Blocked sites are blocked. It ends only when that Focus turns off.
_Avoid_: Work session, block

**Allowance**:
A time-limited exception that makes one Blocked site reachable during a Session.
_Avoid_: Unblock, exception, pass

**Friction**:
The deliberate obstacles (a countdown, a typed reason) the user must get through before loosening a block.
_Avoid_: Confirmation, delay

### Pomodoro

**Pomodoro Cycle**:
One run of alternating Actives and Breaks, from the moment the user starts it until it ends. It runs with or without a Session, but never blocks anything by itself.
_Avoid_: Pomodoro (on its own), timer

**Plan**:
The shape of a Planned Cycle chosen before it starts: how long each Active and each Break lasts, and how many Actives there are. Breaks fall only between Actives, never after the last one.
_Avoid_: Preset, schedule

**Planned Cycle**:
A Pomodoro Cycle that follows a Plan and ends when its last Active ends.

**Free Cycle**:
A Pomodoro Cycle without a Plan: each Active lasts as long as the user wants, and the Break that follows is sized from it.
_Avoid_: Exploration mode, open mode

**Phase**:
One timed stretch of a Pomodoro Cycle: either an Active or a Break.

**Active**:
A Phase of focused work. It ends only when the user ends it, never on its own.
_Avoid_: Pomodoro (for a single interval), work phase, work interval

**Break**:
A Phase of rest between Actives. During a Session, all Blocked sites are reachable until it ends, which it does on its own; a Snooze can reopen it, and the next Active waits for the user.
_Avoid_: Pause, rest

**Snooze**:
A short, capped extension of a Break the user asks for once it has ended, before starting the next Active.
_Avoid_: Extend, postpone

**Wrap-up**:
The minutes left over between the end of a Planned Cycle and the time the user said they had, meant for tidying up before the next sitting. Snoozes eat into it first.
_Avoid_: Slack, buffer, spare time

**Idle**:
The stretch between the end of a Break and the moment the user starts the next Active.
_Avoid_: Waiting, paused

**Overtime**:
The time an Active runs past its planned length because the user kept working.

**Cut short**:
Said of a Phase the user ended before its planned length.
_Avoid_: Undertime, aborted

**Shortfall**:
The planned time a cut-short Active did not cover.
_Avoid_: Undertime
