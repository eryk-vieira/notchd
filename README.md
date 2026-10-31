# notchd

![notchd in its four states: compact, peek, OSD and expanded](docs/images/hero.webp)

A dynamic notch for Wayland desktops, built with Quickshell. It hangs from an edge of the focused screen (the top by default) and shows modules: media, OSD, script activities, system resources, a timer, or anything you write. You can have several notches, each with its own modules and place, and one on every monitor.

It is a **notch framework, not a shell**. Modules show what the system is already doing; they never take over a system service. The notch is not a notification daemon, a launcher or a lock screen, so it sits on top of whatever desktop you already have.

## Install

notchd runs inside a *host*: the desktop-specific wiring around the generic core.

- **Omarchy**: the repository is an Omarchy shell plugin (`eryk.notchd`), with volume/brightness OSD and the compact view in the bar. See [hosts/omarchy](hosts/omarchy/README.md).
- **Any other Wayland compositor with layer-shell**: the repository is also a standalone Quickshell config (`qs -p <checkout>`). See [docs/standalone.md](docs/standalone.md).

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
- `"notch"`: compact hangs from its edge all the time, Mac style.

Hold the hanging notch for a moment, then drag it to move it (a quick click only pins it open): it closes as it is picked up, jumps to the screen edge nearest the pointer as you go, sits with its middle under the pointer, snaps to the middle of an edge when close to it, and stays where you drop it. With more than one monitor you can drag it onto another one: a preview shows it there, and the monitor you drop it on becomes its home, where it stays whichever monitor has focus. A peek shows on the notch, and also at the top of the monitor you work on if no notch there shows it. The volume and brightness OSD, standalone, shows in its own place on the monitor you work on. If that monitor shows a workspace left out of `workspaces`, the drop adds it; on another such workspace later, the notch goes back to the monitors whose workspace takes it. `draggable: false` turns dragging off, and `recenter` over IPC puts it back at the top, following focus.

The drop is stored as `position`, which you can also set by hand: `{"edge": "left", "offset": 0.3, "screen": "eDP-1"}`. `edge` is `"top"` (the default), `"bottom"`, `"left"` or `"right"`; `offset` runs from 0 (the left or top end) to 1, 0.5 being the middle of the stretch the bar leaves free; at either end (or close enough that its shoulder would not fit) the notch sits flush in the corner, square against the screen's side or the bar; `screen` names the home monitor (none: follow focus; `"all"`: a copy on every monitor, see [Several notches](#several-notches)). On a side edge peeks and the expanded notch keep their layout and the notch grows sideways; the closed notch runs down the edge with each module's vertical view (media: artwork over the equalizer; activities: icon over a progress bar) and the volume and brightness OSD stands its bar up. A module without a vertical view shows a dot. In `"bar"` style the notch stays in the middle of the bar, wherever the bar is, on every monitor.

A hanging notch covers the windows under it. `reserveSpace: true` keeps windows clear of it instead: the compositor reserves a strip as deep as the closed notch, along the whole of its edge on its home monitor, or on every monitor it may hang on while it follows focus (layer-shell can only reserve whole edges). At rest that is the thin lip; while a module is active, a compact notch's height. It grows at once and shrinks as soon as the notch has collapsed, so windows move when music starts or stops or an activity comes and goes, not for peeks: volume, brightness and the expanded notch open over windows. It does nothing in `"bar"` style.

`workspaces` limits where the closed notch shows, e.g. `[1, 2, 3]` (ids or names). When the focused screen shows another workspace, the closed notch moves to a screen that shows one of them, or hides if none does; in `"bar"` style the bar indicator hides on those screens. Peeks and the open notch still show, whatever the workspace, so the volume OSD never goes missing. Reserved space follows too: a screen showing a workspace without the notch reserves nothing, so switching a screen between the two moves its windows. It needs a compositor adapter that knows workspaces (Hyprland today).

## Modules

| Id | Shows |
|---|---|
| `media` | what's playing over MPRIS: artwork, title, progress and controls; peeks on a new track. Its equalizer glides at 60 fps; `"media": { "equalizer": "light" }` (settings: Modules › Now playing › Equalizer) makes it jump about six times a second instead, for about 1 % of a CPU core rather than 8 % while music plays |
| `activities` | whatever scripts push over IPC: a deploy, a build, a download (see [docs/ipc.md](docs/ipc.md#activities)) |
| `resources` | CPU, memory and the disk holding `/`: a bar each, expanded, and their percentages in the closed notch. One that runs short (90 % or more; the CPU for about 10 s in a row) turns red and peeks once. `"resources": { "compact": "short" }` (settings: Modules › Resources › Closed notch) keeps them out of the closed notch until one runs short. Linux only. Not loaded by default: add it to `modules` |
| `timer` | a countdown or a pomodoro, started from the expanded notch (5, 15, 25 min, Pomodoro) or with `timer 25m` over [IPC](docs/ipc.md#timer). The closed notch shows the time left; at the end it peeks, even over the open notch, and sends a desktop notification. A pomodoro runs its focus rounds and short breaks, then a long break, and stops. Settings: Modules › Timer (lengths, rounds, starting each phase on its own, the notification). Not loaded by default |
| `osd` | volume and brightness, Omarchy host only (see [hosts/omarchy](hosts/omarchy/README.md)). Standalone: no notch shows it, it has a place of its own, at the top center of the monitor you work on, over any notch there. `"osd": { "position": { "edge": "bottom", "offset": 0.5 } }` moves it and `"osd": { "enabled": false }` switches it off (settings: Modules › OSD) |

A **standalone** module (the OSD) has a fixed job and a place of its own: no notch shows it, even one whose `modules` list it. It loads unless `<id>.enabled` is `false`, shows on the monitor you work on where `<id>.position` (`edge`, `offset`) says, top center by default, and draws over any notch that hangs there, which hides until it goes.

To write your own, see [docs/modules.md](docs/modules.md).

## Several notches

`notches` lists them, each with its own modules and place: the media player at the top, script activities at the bottom of the laptop screen, say. A notch takes the keys marked *per notch* in the table below; the ones it leaves out come from the top level of the config, then their defaults (`position` key by key). Without `notches` there is one notch, made of the top-level keys.

```json
{
  "reserveSpace": true,
  "notches": [
    { "id": "main", "modules": ["media"], "position": { "screen": "all" } },
    { "id": "jobs", "modules": ["activities"], "position": { "edge": "bottom", "screen": "eDP-1" } }
  ]
}
```

- `position.screen` decides where each one is: following focus (none), on one monitor (its name), or on every monitor (`"all"`), each with a copy of its own that you hover, pin and drag on its own.
- A module may show in several notches. Its peek shows in each of them: on the focused monitor for a notch on every monitor (or one that follows focus), the others keeping what they show, and where it is for a notch kept on one monitor. When no notch with the module is on the monitor you work on, the peek also shows there, once, at the top. The volume and brightness OSD is standalone: it shows in its own place on the monitor you work on, never in a notch. So changing the volume on the laptop shows it there, and the notch with the music stays on the ultrawide.
- The host's bar holds one notch's compact state: the first notch in `"bar"` style. The others hang. A notch in the bar has a copy on every monitor, one per bar.
- Notches never sit on each other. On the same edge of a monitor they go side by side, each as near its `offset` as the others let it; when one grows (music starts) its neighbors make room. Notches that come within a few pixels of each other (or are dropped near one) join flush into one shape, as deep as the deepest of them. One that opens (a peek, the pointer) grows from where it is and pushes its neighbors aside, staying joined to them: in the middle of the edge it grows evenly to both sides, against the screen's side it grows away from it. A neighbor that no longer fits on the edge hides until it closes.
- Notches that share an edge reserve the deepest of them (`reserveSpace`), not the sum.
- `id` names a notch for IPC (`openNotch jobs`); without one the first is `main` and the others `notch-2`, `notch-3`...

In the settings window, pick the notch to set up at the top of the Notches page, which has everything that notch has of its own (modules, compact style, position, workspaces); Add notch puts a new one on a free edge, and removing all but one puts its keys back at the top level.

## Config

The config lives in `$XDG_CONFIG_HOME/notchd/config.json` (usually `~/.config/notchd/config.json`), outside the source tree, so plugin updates never touch it. A missing file means every key is at its default. A file you create by hand is picked up within a couple of seconds, and edits apply live.

| Key | Default | |
|---|---|---|
| `modules` | `["media", "activities"]` | module ids to show, in order; *per notch* |
| `compactStyle` | `"bar"` | see above; *per notch* |
| `hoverOpenDelay` | `120` | ms |
| `hoverCloseDelay` | `300` | ms |
| `position` | top, middle, following focus | `{ "edge", "offset", "screen" }`: where the hanging notch sits (`"notch"` style); see above; *per notch* |
| `draggable` | `true` | drag the hanging notch to move it (`"notch"` style); *per notch* |
| `reserveSpace` | `false` | keep windows clear of the closed notch (`"notch"` style); see above; *per notch* |
| `workspaces` | every one | workspaces the closed notch shows on; see above; *per notch* |
| `notches` | one notch | `[{ "id", ...per-notch keys }]`; see [Several notches](#several-notches) |

Hosts add their own keys; the standalone host, for example, adds `topOffset` and `theme`. A module's own settings live under its id, `resources` for example. A key missing from the file falls back to its default.

## Settings

The gear in the expanded notch (or the `settings` IPC method) opens the settings window: a sidebar of pages, and on each page its fields grouped by section. Every change applies at once and is written back to the config file; there is no Apply button. Clearing a field, or picking its default, removes the key. Ctrl+Tab cycles pages; Esc closes.

## IPC

Scripts drive the notch through Quickshell IPC: push an activity, open the notch, change a config key. See [docs/ipc.md](docs/ipc.md).

```sh
omarchy-shell eryk.notchd push '{"id":"deploy","title":"Deploying api","progress":40,"sticky":true}'
```

## Documentation

- [docs/modules.md](docs/modules.md): writing a module
- [docs/standalone.md](docs/standalone.md): the standalone host
- [docs/hosts.md](docs/hosts.md): what a host provides, for porting notchd to another desktop
- [docs/settings.md](docs/settings.md): the settings schema, pages and controls
- [docs/theming.md](docs/theming.md): theme tokens
- [docs/ipc.md](docs/ipc.md): IPC methods
- [DEVELOPMENT.md](DEVELOPMENT.md): working on notchd itself
- [CHANGELOG.md](CHANGELOG.md)

## License

MIT, see [LICENSE](LICENSE). The Omarchy host's `osd` module adapts code from Omarchy, which is also MIT; see [NOTICE](NOTICE).
