# notchd (standalone host)

The notch as its own Quickshell config, for any Wayland compositor with layer-shell. It uses the Hyprland adapter when `HYPRLAND_INSTANCE_SIGNATURE` is set, and the generic one otherwise. The generic adapter keeps the notch on the first screen and doesn't hide it for fullscreen apps.

```sh
qs -p hosts/standalone
NOTCHD_CONFIG=~/notchd-test.json qs -p hosts/standalone   # another config file
```

Differences from the Omarchy host:

- **No bar indicator**, so `compactStyle` is always `"notch"`.
- **No `osd` module yet.** It needs its own volume and brightness sources.
- **Theme from the config.**

## Config

`$NOTCHD_CONFIG`, or `~/.config/notchd/config.json` by default, the same file the Omarchy host uses. Each host ignores the other's keys; an Omarchy-only module such as `osd` in `modules` is skipped with a warning in the log. It takes the core keys (see the root README), plus:

| Key | Default | |
|---|---|---|
| `topOffset` | `0` | gap above the notch, such as your bar's height |
| `theme` | `{}` | any of `foreground`, `background`, `accent`, `fontFamily`, `spacingScale` |

All of these keys except `spacingScale` are in the settings window too.

Use a Nerd Font for `fontFamily` so module icons render.

## IPC

```sh
qs -p hosts/standalone ipc call notchd push '{"id":"deploy","title":"Deploying api","progress":40,"sticky":true}'
qs -p hosts/standalone ipc call notchd clear deploy
qs -p hosts/standalone ipc call notchd settings          # settings window (also the gear)
qs -p hosts/standalone ipc call notchd set topOffset 32   # change one key; '' resets it
qs -p hosts/standalone ipc call notchd state
```
