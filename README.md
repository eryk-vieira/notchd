# eryk.notch

A dynamic notch that hangs under the bar's centered clock on the focused monitor.

| State | When | Shows |
|---|---|---|
| rest | nothing active | a small lip (nothing in bar style) |
| compact | a module is active | the highest-priority active module's `compact` view under the clock, or its `barView` in the bar |
| peek | a module calls `requestPeek()` | that module's `peek` view, for a few seconds |
| expanded | hover (click pins it, click outside unpins) | the `expanded` view of every active module |

Over a fullscreen app only peeks show.

## Style

The `"compactStyle"` key in `config.json` sets the style, and it applies live:

- `"bar"` (default): rest and compact live in the bar indicator (the `eryk.notch` bar widget, placed right after the clock). The notch only drops below the bar to peek or expand, so it never sits over windows. Hovering the indicator expands the notch on that monitor, and clicking pins it.
- `"notch"`: compact hangs under the clock all the time, Mac style, and covers the top of windows there.

## Layout

- `Service.qml`: all state (config, modules, mode, peeks, hover, IPC). Modules see it as `notch`.
- `Notch.qml`: the overlay surface under the bar.
- `BarIndicator.qml`: the bar widget, which renders `barView` (or `compact`).
- `modules/`: one file per element type.

The plugin is enabled by its bar entry (`.bar.layout.center` in `~/.config/omarchy/shell.json`). It is not listed in `plugins[]`. If it is listed there, `omarchy bar put` thinks it is already on the bar and does nothing.

## Modules

`config.json` lists the modules to load, in order. Each id is a file in `modules/`:

- `osd`: volume, brightness, mic and keyboard light. It owns the `osd` IPC target that every `omarchy osd` call uses, so the stock OSD must stay disabled: `omarchy plugin disable omarchy.osd`. Undo it with `omarchy plugin enable omarchy.osd`.
- `media`: MPRIS now playing. Compact shows artwork plus an equalizer, a new track peeks, and expanded shows controls.
- `activities`: generic items pushed by scripts (see below).

### Adding a module

Create `modules/<name>.qml` with a `NotchModule` root (see `modules/NotchModule.qml`), then add `"<name>"` to `config.json`.

```qml
import QtQuick
import qs.Commons

NotchModule {
  id: m
  title: "Example"
  priority: 60          // higher wins the compact slot / outranks lower peeks
  active: true          // show in compact/expanded while true
  // urgentPeek: true   // peek even while expanded by hover

  compact: Component { Text { text: "hi"; color: Color.foreground } }
  barView: Component { Text { text: "hi"; color: Color.foreground } }  // optional, for the bar
  peek: Component { Text { text: "hello!"; color: Color.foreground } }
  expanded: Component { Text { text: "details"; color: Color.foreground } }

  // m.requestPeek(3000) pops the notch open with `peek` for 3 s.
}
```

Views are Components that size themselves through `implicitWidth`/`implicitHeight`; the notch springs to fit. Expanded views get a fixed width.

After changing QML, run `omarchy restart shell`, because the hot reload keeps serving the old compiled QML. Edits to `config.json` apply live.

## Activities from scripts

```sh
omarchy-shell eryk.notch push '{"id":"deploy","icon":"󰜎","title":"Deploying api","subtitle":"staging","progress":40,"sticky":true}'
omarchy-shell eryk.notch push '{"id":"deploy","progress":80,"peek":false,"sticky":true,"title":"Deploying api"}'
omarchy-shell eryk.notch clear deploy     # clear "" removes all
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
omarchy-shell eryk.notch toggle | open | close
omarchy-shell eryk.notch state     # mode, current peek, modules
```
