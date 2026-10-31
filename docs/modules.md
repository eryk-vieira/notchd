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
  // peekOnFocusedScreen: true  // peek once, on the focused screen only (feedback, like the OSD)

  compact: Component { Text { text: "hi"; color: Theme.foreground } }
  barView: Component { Text { text: "hi"; color: Theme.foreground } }  // optional, for the bar
  verticalCompact: Component { Text { text: "h\ni"; color: Theme.foreground } }  // optional, for a side edge
  verticalPeek: Component { Text { text: "h\ne\ny"; color: Theme.foreground } }  // optional, for a side edge
  peek: Component { Text { text: "hello!"; color: Theme.foreground } }
  expanded: Component { Text { text: "details"; color: Theme.foreground } }

  // m.requestPeek(3000) pops the notch open with `peek` for 3 s.
}
```

A module that is `active` but has no `compact` view right now leaves the closed notch at rest and still shows when expanded: the `resources` module, set to `"short"`, binds `compact` to null until a resource runs short.

## Settings

A module lists fields of its own in `settings`, in the settings schema's format (see [settings.md](settings.md)) with `key` relative to the module, and reads them with `setting(key)`: the config's value, else the field's default. They are stored under the module's id and show on the General page, under the module's title, while some notch loads it.

```qml
settings: [
  { key: "compact", type: "choice", label: "Closed notch", default: "always",
    options: [{ value: "always", label: "Always" }, { value: "short", label: "When running short" }] }
]
readonly property bool alwaysCompact: m.setting("compact") !== "short"   // config: "resources": { "compact": "short" }
```

A module's settings apply to every notch, since it loads once. Pick an id that isn't a config key (`modules`, `position`, `theme`...).

## The scope rule

A module **shows** state, it does not **own** it. A notifications module mirrors toasts; it does not register as the notification server. The one exception today is the Omarchy `osd` module, which takes the `osd` IPC target from the stock OSD plugin (and says so in its README).

## Rules

- Sizes go through `Theme.space(px)` and text through `Theme.font.*`, so the module follows the host's density and fonts.
- Colors come from the theme tokens (`Theme.foreground`, `Theme.muted`, `Theme.line`, …), never hard-coded or ad-hoc alphas. See [theming.md](theming.md).
- Views are Components that size themselves through `implicitWidth`/`implicitHeight`; the notch springs to fit. Expanded views get a fixed width.
- `notch` (set by the service) is the `NotchService`; read state from it, never from another module's internals. A module may show in several notches at once, so the service answers for all of them: `notch.expanded` (some notch is open) and `notch.peeking(module)` (some notch shows that module's peek). Each notch picks the vertical views on a side edge itself.
- Views never rotate. On a side edge the notch runs down the edge for `verticalCompact` and `verticalPeek`; `peek` (for a module without a `verticalPeek`) and `expanded` keep their layout and the notch grows sideways to hold them. Give a side-edge view when a module has something narrow to show: the built-ins stack artwork over the equalizer (media), an icon over a progress bar (activities), each short resource's icon over its number (resources), and stand the OSD's bar up.
- Every change on screen redraws the notch's whole window, at the monitor's refresh rate while something moves. Don't animate without pause: a `Behavior` that never settles, or a timer of a few hundred ms easing into each value, keeps the window drawing frames for as long as it runs. Step such a view instead, and stop its timer while the view is hidden (`running: … && visible`): a notch concealed over a fullscreen app hides its card. `make bench` measures what a view costs.

## Which view shows when

| Property | Used when |
|---|---|
| `compact` | the module is the highest-priority active one with a compact view, and compactStyle is `"notch"` |
| `barView` | as `compact`, in the host's bar indicator (compactStyle `"bar"`); falls back to `compact` |
| `verticalCompact` | as `compact`, with the notch on a side edge, and in a vertical bar: narrow and tall. Without one the notch shows a dot there |
| `verticalPeek` | as `peek`, on a side edge: narrow and tall. Without one, `peek` shows there |
| `peek` | the module called `requestPeek(ms)` and won: a pinned notch never peeks, hover only lets `urgentPeek` modules through, and a peek on screen is not cut short by a lower-priority one. It shows in every notch that lists the module (on the focused monitor for a notch on every monitor), and at the top of the focused monitor when no notch with the module is there. With `peekOnFocusedScreen` it shows once, on the focused monitor only: in the first notch there that lists the module, else at the top. A host's system module (`systemModules`, like the Omarchy OSD) loads even when no notch lists it, and its peek borrows any notch on the focused monitor before falling back to the top |
| `expanded` | the notch is expanded and the module is active; every active module's view stacks, highest priority first |

The rules live in `core/State.js` and are tested in `tests/state.test.mjs`.

## Loading

The config's `modules` (each notch's, in a config with `notches`) lists ids in order; the service loads every module some notch lists, once. An id resolves to a host module first, then a built-in. An unknown id, or a file whose root is not a `NotchModule`, is skipped with a warning in the log.
