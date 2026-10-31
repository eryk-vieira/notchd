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
| `open`, `close`, `toggle` | pin the notch open, close it, flip |
| `settings` | open or close the settings window |
| `set <key> <json>` | change one config key, as the settings window does; an empty value resets it |
| `state` | mode, compact style, reserved space, workspaces, current peek and modules, as JSON |

```sh
omarchy-shell eryk.notchd set hoverOpenDelay 200
omarchy-shell eryk.notchd set compactStyle '"notch"'
omarchy-shell eryk.notchd set hoverOpenDelay ''        # back to the default
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
