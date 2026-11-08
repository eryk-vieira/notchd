# Herdr module

This module is a program and a terminal in one custom module. The program shows
a summary of a local Herdr session in any notch that lists `herdr`: agent
states, workspace and pane counts; it uses Herdr's snapshot and event socket and
starts no agents. The terminal (`"terminal": { "command": "herdr" }` in
`module.json`) runs Herdr's own interface below that summary. Its icon is
bundled as `herdr.svg`. It works with an existing notchd installation; no daemon
release or rebuild is needed. The `herdr` CLI must be on `PATH`.
The logo is adapted from Herdr's Apache-2.0-licensed artwork; see
[LICENSE-HERDR](LICENSE-HERDR) and the repository's [NOTICE](../../../../NOTICE).

Install it from this repository:

```sh
mkdir -p ~/.config/notchd/modules
cp -r docs/examples/modules/herdr ~/.config/notchd/modules/
```

Then open notchd Settings, add a notch if desired, and select **Herdr** under
that notch's **Loaded modules**. Its settings page has switches for blocked and
done peeks, their duration, and optional desktop notifications. The first
snapshot establishes a baseline and never announces old states. If Herdr stops,
the module waits for it to return.

The module treats `working → idle` as a completed task too. Herdr can report
`idle` instead of `done` when a completion has already been seen in a client;
status events are handled immediately, and periodic snapshots reconcile the
counts if an event is missed.

Closed, the notch shows the summary's compact view; open, the summary's metrics
sit above Herdr's terminal, which fills the rest. The terminal starts when the
notch is opened and keeps running while it is closed; the summary and
notifications continue to work meanwhile. The terminal's own settings (the
`directory` it starts in, its `command`, `width`, `height`, `font` and
`idleMinutes`) are on the module's settings page, under the module's id in the
config; `terminal herdr toggle` over IPC opens or closes it. Its width defaults
to 760 px, which aligns both views.

A config from before the module had its own terminal glued two modules in a
notch with `tabs: false`: `herdr` and a terminal with the command `herdr`
(`herdr-terminal`). That still works, but the two are not merged for you: list
only `herdr` in the notch, and delete the extra terminal (Modules › Yours, the
trash can, or `notchd ipc module remove herdr-terminal`).

The settings apply to this module wherever it appears. If several notches list
it, notchd's ordinary peek routing shows the same alert in each. Herdr's
`done` state means a completed agent has not been seen; focusing it clears that
state. This module follows the local default session unless **Session** names
another local session.
