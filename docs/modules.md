# Writing a module

A module is a QML file whose root is a `NotchModule`. Built-ins live in `core/modules/` and import the core with `import ".."`. A host's modules live in its own folder (the Omarchy host's in `hosts/omarchy/modules/`, importing `"../../../core"`) and register through the service's `hostModules`.

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

## The scope rule

A module **shows** state, it does not **own** it. A notifications module mirrors toasts; it does not register as the notification server. The one exception today is the Omarchy `osd` module, which takes the `osd` IPC target from the stock OSD plugin (and says so in its README).

## Rules

- Sizes go through `Theme.space(px)` and text through `Theme.font.*`, so the module follows the host's density and fonts.
- Colors come from the theme tokens (`Theme.foreground`, `Theme.muted`, `Theme.line`, …), never hard-coded or ad-hoc alphas. See [theming.md](theming.md).
- Views are Components that size themselves through `implicitWidth`/`implicitHeight`; the notch springs to fit. Expanded views get a fixed width.
- `notch` (set by the service) is the `NotchService`; read state from it, never from another module's internals.

## Which view shows when

| Property | Used when |
|---|---|
| `compact` | the module is the highest-priority active one with a compact view, and compactStyle is `"notch"` |
| `barView` | as `compact`, in the host's bar indicator (compactStyle `"bar"`); falls back to `compact` |
| `peek` | the module called `requestPeek(ms)` and won: a pinned notch never peeks, hover only lets `urgentPeek` modules through, and a peek on screen is not cut short by a lower-priority one |
| `expanded` | the notch is expanded and the module is active; every active module's view stacks, highest priority first |

The rules live in `core/State.js` and are tested in `tests/state.test.mjs`.

## Loading

The config's `modules` lists ids in order. An id resolves to a host module first, then a built-in. An unknown id, or a file whose root is not a `NotchModule`, is skipped with a warning in the log.
