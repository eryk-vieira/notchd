# omarchy-notchd (Omarchy host, plugin `eryk.notchd`)

notchd as an Omarchy shell plugin. It adds three things to the core:

- **Bar indicator** (`BarIndicator.qml`): compact lives in the bar, right after the clock (`compactStyle: "bar"`, the default). Hovering it drops the notch on that monitor, and clicking pins it.
- **`osd` module** (`modules/osd.qml`): volume, brightness, mic and keyboard light. It owns the `osd` IPC target that every `omarchy osd` call uses, so the stock OSD must stay disabled: `omarchy plugin disable omarchy.osd`. Undo it with `omarchy plugin enable omarchy.osd`.
- **Omarchy's theme**: `Service.qml` maps `qs.Commons` `Color`/`Style` onto the core's `Theme`, so the notch follows theme switches and `[font] base-size`.

## Install (development)

```sh
ln -sfn "$PWD/hosts/omarchy" ~/.config/omarchy/plugins/eryk.notchd
omarchy restart shell
```

The plugin is enabled by its bar entry (`.bar.layout.center` in `~/.config/omarchy/shell.json`). It is not listed in `plugins[]`. If it is listed there, `omarchy bar put` thinks it is already on the bar and does nothing.

After changing QML, run `omarchy restart shell`, because the hot reload keeps serving the old compiled QML. Config changes apply live.

## Distribution

`hosts/omarchy/core` is a symlink. The shell loads it, but `omarchy plugin validate` (and so `omarchy plugin add`/`update`) rejects symlinks. `scripts/build-omarchy.sh` builds `dist/eryk.notchd` with the core copied in and validates it.

## Config

`~/.config/notchd/config.json`, edited by hand, through the settings window (the gear in the expanded notch) or with `omarchy-shell eryk.notchd set`. It takes the core keys (see the root README); the default `modules` here include `osd`.

## Activities from scripts

```sh
omarchy-shell eryk.notchd push '{"id":"deploy","icon":"󰜎","title":"Deploying api","subtitle":"staging","progress":40,"sticky":true}'
omarchy-shell eryk.notchd push '{"id":"deploy","progress":80,"peek":false,"sticky":true,"title":"Deploying api"}'
omarchy-shell eryk.notchd clear deploy     # clear "" removes all
```

Fields:

- `id`: the same id updates the item in place.
- `icon`: a Nerd Font glyph.
- `title`, `subtitle`.
- `progress`: 0 to 100; omit it for no bar.
- `sticky`: keep the item in compact/expanded until it is cleared. Without it, the item only peeks.
- `peek`: set to `false` to update without popping open.
- `duration`: peek length in ms.

## Other IPC

```sh
omarchy-shell eryk.notchd toggle | open | close
omarchy-shell eryk.notchd settings  # settings window (also the gear in the expanded notch)
omarchy-shell eryk.notchd set hoverOpenDelay 200   # change one key; '' resets it
omarchy-shell eryk.notchd state     # mode, current peek, modules
```
