# Omarchy host (plugin `eryk.notchd`)

notchd as an Omarchy shell plugin. The repository root is the plugin folder: `manifest.json` there points at the QML in this directory. It adds three things to the core:

- **Bar indicator** (`BarIndicator.qml`): compact lives in the bar, right after the clock (`compactStyle: "bar"`, the default); in a vertical bar it shows the module's vertical view, or a dot. Hovering it drops the notch on that monitor, out of whichever edge the bar is on, and clicking pins it. It hides on monitors showing a workspace left out of `workspaces`.
- **`osd` module** (`modules/osd.qml`): volume, brightness, mic and keyboard light. With the notch on a side edge its bar stands up. It owns the `osd` IPC target that every `omarchy osd` call uses, so the stock OSD must stay disabled: `omarchy plugin disable omarchy.osd`. Undo it with `omarchy plugin enable omarchy.osd`.
- **Omarchy's theme**: `Service.qml` maps `qs.Commons` `Color`/`Style` onto the core's `Theme`, so the notch follows theme switches and `[font] base-size`.

## Install

```sh
omarchy plugin add https://github.com/eryk-vieira/notchd.git
omarchy plugin disable omarchy.osd      # the notch takes over the OSD
omarchy restart shell
```

For development, link a checkout instead (see [DEVELOPMENT.md](../../DEVELOPMENT.md)):

```sh
ln -sfn "$PWD" ~/.config/omarchy/plugins/eryk.notchd
omarchy restart shell
```

The plugin is enabled by its bar entry (`.bar.layout.center` in `~/.config/omarchy/shell.json`). It is not listed in `plugins[]`. If it is listed there, `omarchy bar put` thinks it is already on the bar and does nothing.

After changing QML, run `omarchy restart shell`, because the hot reload keeps serving the old compiled QML. Config changes apply live.

## Config

`~/.config/notchd/config.json`, edited by hand, through the settings window (the gear in the expanded notch) or with `omarchy-shell eryk.notchd set`. It takes the core keys (see the [README](../../README.md#config)); the default `modules` here include `osd`.

## IPC

`omarchy-shell eryk.notchd <method>`; the methods and the activity fields are in [docs/ipc.md](../../docs/ipc.md).

```sh
omarchy-shell eryk.notchd push '{"id":"deploy","icon":"󰜎","title":"Deploying api","progress":40,"sticky":true}'
omarchy-shell eryk.notchd settings
```
