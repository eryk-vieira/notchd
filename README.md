# notchd

A dynamic notch for Wayland desktops, built with Quickshell. It hangs from the top edge of the focused screen and shows modules: media, OSD, script activities, or anything you write.

It is a **notch framework, not a shell**. Modules show what the system is already doing; they never take over a system service. The notch is not a notification daemon, a launcher or a lock screen, so it sits on top of whatever desktop you already have.

## Layout

```
core/                 the framework: no desktop-specific code
  NotchService.qml    state: config, modules, mode, peeks, hover, IPC
  NotchSurface.qml    the overlay that draws the notch
  NotchModule.qml     base type for modules
  Theme.qml           visual tokens (singleton), fed by the host
  *Compositor.qml     compositor adapters (Hyprland, generic)
  modules/            built-in modules: media, activities
hosts/
  omarchy/            Omarchy shell plugin (eryk.notchd); see its README
  standalone/         its own Quickshell config, for any compositor
scripts/
  build-omarchy.sh    self-contained Omarchy plugin in dist/
```

Each host links `core` in with a relative symlink (`hosts/*/core -> ../../core`), so `import "core"` works from the host folder.

## States

| State | When | Shows |
|---|---|---|
| rest | nothing active | a small lip (nothing in bar style) |
| compact | a module is active | the highest-priority active module's `compact` view, or its `barView` in the host's bar |
| peek | a module calls `requestPeek()` | that module's `peek` view, for a few seconds |
| expanded | hover (click pins it, click outside unpins) | the `expanded` view of every active module |

Over a fullscreen app only peeks show.

`compactStyle` in the config sets where compact lives:

- `"bar"`: in the host's bar indicator. The notch only drops out to peek or expand. Only hosts with a bar indicator support it; that is only the Omarchy host today.
- `"notch"`: compact hangs from the top edge all the time, Mac style.

## What a host provides

`NotchService`:

| Property | Meaning |
|---|---|
| `ipcTarget` | IPC target name for scripts |
| `configPath` | absolute path of the JSON config (watched, live); defaults to `$XDG_CONFIG_HOME/notchd/config.json` |
| `hostModules` | `{ id: url }` of modules the host ships; they win over built-ins |
| `barStyleAvailable` | whether the host has a bar indicator for `compactStyle: "bar"` |
| `defaultModules` | modules to load when the config lists none |
| `hostSettingsSchema` | settings-window fields for the host's own config keys (see [Settings](#settings)) |

`NotchSurface`:

| Property | Meaning |
|---|---|
| `svc` | the service |
| `compositor` | a compositor adapter (see `core/GenericCompositor.qml` for the contract) |
| `barHeight`, `barOnTop`, `barHidden` | the host's bar, so the notch hangs under it |
| `layerNamespace` | layer-shell namespace |

`Theme.provider`: an object with any of `foreground`, `background`, `accent`, `fontFamily`, `fontCaption`, `fontBodySmall`, `fontBody`, `fontHeading`, `fontDisplay` and `spacingScale`. Missing keys use defaults.

## Config

The config lives in `$XDG_CONFIG_HOME/notchd/config.json` (usually `~/.config/notchd/config.json`), outside the source tree, so plugin updates never touch it. A missing file means every key is at its default. The settings window creates the file on the first change, and a file you create by hand is picked up within a couple of seconds.

| Key | Default | |
|---|---|---|
| `modules` | `["media", "activities"]` | module ids to load, in order |
| `compactStyle` | `"bar"` | see above |
| `hoverOpenDelay` | `120` | ms |
| `hoverCloseDelay` | `300` | ms |

Hosts add their own keys; the standalone host, for example, adds `topOffset` and `theme`. A key missing from the file falls back to its default.

## Settings

The gear in the expanded notch (or the `settings` IPC method) opens a settings window. It is an ordinary toplevel window with a fixed size, so tiling compositors float it, and it takes keyboard input. Every change applies at once and is written back to the config file; there is no Apply button. Clearing a field removes the key, so it goes back to its default.

The form is generated from `NotchService.settingsSchema`: the core's fields, then the host's `hostSettingsSchema`. Each field is an object:

| Key | |
|---|---|
| `key` | config key; dotted for nested objects (`theme.accent`) |
| `type` | `choice`, `integer`, `string`, `color` or `modules` |
| `label`, `help` | text shown next to and under the control |
| `section` | heading the field sits under |
| `default` | value shown while the key is absent |
| `options` | `[{ value, label }]`, for `choice` |
| `min`, `max`, `step`, `unit` | for `integer` (a slider) |

## Writing a module

A module is a QML file whose root is a `NotchModule`. Built-ins live in `core/modules/` and import the core with `import ".."`. A host's modules import it with `import "../core"` and register through `hostModules`.

```qml
import QtQuick
import ".."

NotchModule {
  id: m
  title: "Example"
  priority: 60          // higher wins the compact slot / outranks lower peeks
  active: true          // show in compact/expanded while true
  // urgentPeek: true   // peek even while expanded by hover

  compact: Component { Text { text: "hi"; color: Theme.foreground } }
  barView: Component { Text { text: "hi"; color: Theme.foreground } }  // optional, for the bar
  peek: Component { Text { text: "hello!"; color: Theme.foreground } }
  expanded: Component { Text { text: "details"; color: Theme.foreground } }

  // m.requestPeek(3000) pops the notch open with `peek` for 3 s.
}
```

Use `Theme.space(px)` for sizes and `Theme.font.*` for text, so the module follows the host's density and fonts. Views are Components that size themselves through `implicitWidth`/`implicitHeight`; the notch springs to fit. Expanded views get a fixed width.

The scope rule: a module **shows** state, it does not **own** it. A notifications module mirrors toasts; it does not register as the notification server.

## IPC

Every host exposes the same methods on its `ipcTarget`:

```
push '<json>'    add or update an activity (see core/modules/activities.qml)
clear <id>       remove one; "" removes all
open | close | toggle
settings         open or close the settings window
set <key> <json> change one config key, e.g. set hoverOpenDelay 200;
                 an empty value resets it to its default
state            mode, current peek, modules
```

For an array, put a space before the bracket: `set modules ' ["media","activities"]'`. Quickshell's CLI reads an argument that starts with `[` as a comma-separated list.

The CLI depends on the host: `omarchy-shell eryk.notchd ...` on Omarchy, `qs -p hosts/standalone ipc call notchd ...` standalone.
