# IPC

Every host exposes the same methods on its `ipcTarget`. The CLI depends on the host:

| Host | Command |
|---|---|
| Omarchy | `omarchy-shell eryk.notchd <method> ...` |
| standalone | `qs -p <checkout> ipc call notchd <method> ...` |

| Method | |
|---|---|
| `push '<json>'` | add or update an activity (below) |
| `clear <id>` | remove one; `""` removes all |
| `open`, `toggle` | pin the first notch open on the focused monitor, or flip it |
| `close` | close every notch |
| `openNotch <id>`, `closeNotch <id>`, `toggleNotch <id>` | the same for one notch, by its `id` (`main`, `notch-2`...), its Name in settings: renaming it breaks a shortcut that names it |
| `agent <id> <command>` | an agent (`claude`, `codex`) by its id: `toggle` opens or closes its notch, `new` starts a new session, `"ask <question>"` opens it and types the question in ([below](#agents)) |
| `claude <command>`, `codex <command>` | the same as `agent claude <command>`, `agent codex <command>` |
| `timer <command>` | the `timer` module: start, pause or stop a countdown or a pomodoro (below) |
| `settings` | open or close the settings window |
| `recenter` | put every notch back in the middle of the top edge, following focus (removes each `position`) |
| `set <key> <json>` | change one config key, as the settings window does; an empty value resets it |
| `state` | as JSON: `notches`, each with its id, reserved space, workspaces, position (where it is), whether it can be dragged, its modules and its `copies` (screen, mode and current peek of each); each `standalone` module's place and the copies that show it; and every loaded module, with an agent's plan `usage` (its limits, whether they are stale and why) |

```sh
omarchy-shell eryk.notchd set hoverOpenDelay 200
omarchy-shell eryk.notchd set position.edge '"left"'
omarchy-shell eryk.notchd set hoverOpenDelay ''        # back to the default
omarchy-shell eryk.notchd set position ''              # back to top-center
omarchy-shell eryk.notchd set notches.1.position.edge '"bottom"'   # the second notch
omarchy-shell eryk.notchd toggleNotch jobs
```

For an array, put a space before the bracket: `set modules ' ["media","activities"]'`. Quickshell's CLI reads an argument that starts with `[` as a comma-separated list.

## Activities

The `activities` module shows whatever scripts push: a deploy, a build, a long download.

```sh
omarchy-shell eryk.notchd push '{"id":"deploy","icon":"󰜎","title":"Deploying api","subtitle":"staging","progress":40,"sticky":true}'
omarchy-shell eryk.notchd push '{"id":"deploy","progress":80,"peek":false,"sticky":true,"title":"Deploying api"}'
omarchy-shell eryk.notchd clear deploy
```

| Field | |
|---|---|
| `id` | the same id updates the item in place |
| `icon` | a Nerd Font glyph |
| `title`, `subtitle` | |
| `progress` | 0 to 100; omit it for no bar |
| `sticky` | keep the item in compact/expanded until it is cleared; without it, the item only peeks |
| `peek` | `false` updates without popping open |
| `duration` | peek length in ms |

## Timer

The `timer` module takes one argument, quoted when it has spaces:

| Command | |
|---|---|
| `25m`, `90s`, `1h30m`, `1:30`, `25` (minutes) | start a countdown |
| `"3m Tea"` | with a label |
| `pomodoro` | start a pomodoro (lengths and rounds in settings: Modules › Timer) |
| `toggle` (or nothing) | pause or resume; a pomodoro waiting for its next phase starts it |
| `pause`, `resume` | |
| `+5m` | add time |
| `skip` | a pomodoro's next phase; a countdown stops |
| `stop` | |

```sh
omarchy-shell eryk.notchd timer "3m Tea"
omarchy-shell eryk.notchd timer pomodoro
omarchy-shell eryk.notchd timer toggle
```

It answers `ok`, `no timer running`, the usage, or `timer module not loaded` when no notch lists `timer`.

## Agents

The agents (`claude`, `codex`) run in a terminal in the notch. `agent <id> toggle` opens the notch that shows one, on its tab, or closes it: bind that to a key, since it finds the notch by the agent it shows, whatever the notch is called or wherever the agent is. From a Hyprland binding:

```sh
bind = SUPER ALT, C, exec, omarchy-shell eryk.notchd agent claude toggle
```

| Command | |
|---|---|
| `toggle` | open the agent's notch (the first that lists it) on its tab, or close it while it shows the agent |
| `new` | a new session: the running one stops (`/resume` brings it back) |
| `"ask <question>"` | open the agent's notch and type the question in, then Enter, once the agent is up; `ask` alone only opens it |

```sh
omarchy-shell eryk.notchd agent claude "ask what does EXDEV mean?"
omarchy-shell eryk.notchd agent codex "ask explain: $(wl-paste --primary)"   # the selected text, as one line
```

It answers `ok`, `no notch shows <id>`, `the terminal needs the qmltermwidget package`, the usage, `<id> module not loaded` when no notch lists it, or `no agent <id>` with the agents there are.
