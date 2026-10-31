# Hosts

The core (`core/`) has no desktop-specific code. A host instantiates it and fills in what only the desktop knows: its IPC name, its bar, its theme, its extra modules. Two exist, and the repository root is both:

- **Omarchy**: `manifest.json` points the Omarchy shell at `hosts/omarchy/*.qml`, which import the core with `import "../../core"`.
- **Standalone**: `shell.qml`, so `qs -p <checkout>` runs it. It has to sit at the root: Quickshell only resolves types from files inside the config folder, so a `hosts/standalone/shell.qml` importing `"../../core"` fails with "NotchSurface is not a type".

No symlinks: `omarchy plugin validate` rejects any inside the plugin folder.

## NotchService

The single source of truth: config, modules, mode, peeks, hover, IPC.

| Property | Meaning |
|---|---|
| `ipcTarget` | IPC target name for scripts |
| `logName` | prefix for log lines; defaults to `ipcTarget` |
| `configPath` | absolute path of the JSON config (watched, live); defaults to `$XDG_CONFIG_HOME/notchd/config.json` |
| `hostModules` | `{ id: url }` of modules the host ships; they win over built-ins |
| `barStyleAvailable` | whether the host has a bar indicator for `compactStyle: "bar"` |
| `compositor` | a compositor adapter; the surface uses it unless given its own, and the `workspaces` setting needs one that knows workspaces |
| `defaultModules` | modules to load when the config lists none |
| `hostSettingsSchema` | settings-window fields for the host's own config keys (see [settings.md](settings.md)) |
| `hostSettingsPages` | extra settings-window pages, or new labels/icons for the core ones |

A host reads its own config keys from `service.config`. A bar indicator asks `service.showsOn(screen)` whether the closed notch belongs on its monitor's workspace.

## NotchSurface

The layer-shell overlay that puts the notch on screen: it picks the screen, places a `NotchCard` (the notch itself, which also renders offscreen) under the bar and routes the pointer.

| Property | Meaning |
|---|---|
| `svc` | the service |
| `compositor` | a compositor adapter (see `core/GenericCompositor.qml` for the contract); defaults to the service's |
| `barHeight`, `barOnTop`, `barHidden` | the host's bar, so the notch hangs under it |
| `layerNamespace` | layer-shell namespace |

With the config's `reserveSpace` on (and `compactStyle` `"notch"`), it also maps one empty window per screen, namespace `<layerNamespace>-reserve`, holding an exclusive zone as deep as the closed notch (`ReservedSpace.qml`: the rest lip, or the tallest compact view seen while a module is active; it grows at once and shrinks once the notch has collapsed, 400 ms later). It sits on the overlay layer, so the compositor stacks it under the bar's own zone; a host bar needs a normal exclusive zone for the strip to land where the notch hangs.

Give the service and the adapter ids that differ from these property names (`service`, `compositorLoader`): `svc: svc` inside the surface reads as the surface's own property.

## Theme

Set `Theme.provider` to an object mapping the host's theme onto the core's tokens. See [theming.md](theming.md).

## Compositor adapters

`HyprlandCompositor` and `GenericCompositor`. An adapter tells the notch which screen is focused, whether a fullscreen window covers it and which workspace each screen shows (`supportsWorkspaces`, `knownWorkspaces`, `activeWorkspace(screen)`); the generic one assumes the first screen, never fullscreen, and no workspaces, which hides the `workspaces` setting. `core/GenericCompositor.qml` has the contract.
