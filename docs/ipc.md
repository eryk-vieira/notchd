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
| `openNotch <id>`, `closeNotch <id>`, `toggleNotch <id>` | the same for one notch, by its `id` (`main`, `notch-2`...) |
| `settings` | open or close the settings window |
| `recenter` | put every notch back in the middle of the top edge, following focus (removes each `position`) |
| `set <key> <json>` | change one config key, as the settings window does; an empty value resets it |
| `state` | as JSON: `notches`, each with its id, compact style, reserved space, workspaces, position (where it is, bar style applied), whether it can be dragged, its modules and its `copies` (screen, mode and current peek of each); and every loaded module |

```sh
omarchy-shell eryk.notchd set hoverOpenDelay 200
omarchy-shell eryk.notchd set compactStyle '"notch"'
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
