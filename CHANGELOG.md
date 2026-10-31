# Changelog

All user-visible changes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/). The version is `manifest.json`'s. Released sections are never edited.

## [Unreleased]

### Added

- `timer` module: a countdown or a pomodoro, started from the expanded notch or with `timer 25m`, `timer pomodoro`, `timer toggle`, `timer +5m`, `timer stop` over IPC. The closed notch shows the time left; at the end it peeks, even over the open notch, and sends a desktop notification. Its lengths, rounds, auto-start and notification are in settings (General › Timer). Not loaded by default.
- `media.equalizer` (settings: General › Now playing › Equalizer): `"smooth"` (the default) glides the bars at 60 fps, `"light"` makes them jump about six times a second, for less CPU.
- `resources` module: CPU, memory and the disk holding `/`, each with a bar and how much is used in the expanded notch, and their percentages in the closed notch. One that runs short (90 % or more; the CPU for about 10 s in a row, so a burst doesn't count) turns red and peeks once. `resources.compact: "short"` (settings: General › Resources › Closed notch) keeps them out of the closed notch until one runs short. Not loaded by default.
- Modules can have settings of their own (`NotchModule.settings`, read with `setting(key)`): stored under the module's id, shown on the General page under its title while it is loaded.
- Notches never sit on each other: on the same edge of a monitor they go side by side, each as near its `offset` as the others let it, and make room when one grows. An open notch grows over its neighbors, which hide until it closes.
- The Omarchy OSD always shows, even when no notch lists `osd`: hosts name system modules (`NotchService.systemModules`) that always load. Their peeks show on the focused monitor, in a notch there (one that lists the module first), else in a default notch at the top.
- Modules can set `peekOnFocusedScreen`: their peek shows once, on the focused monitor only, in the first notch there that shows the module, else at the top. The Omarchy OSD sets it, so the volume and brightness show where you change them and nowhere else.
- Settings: everything a notch has of its own (name, modules, compact style, position, workspaces) is on one page, Notches, under the notch picker; General has what applies to every notch.
- Several notches (`notches`; settings: the Notches page, with the notch picker at its top and everything a notch has of its own below it): each with its own modules, compact style, position, workspaces and reserved space, inheriting the top-level keys it leaves out. A module may show in several. IPC gets `openNotch`, `closeNotch` and `toggleNotch` by notch id, and `state` lists the notches and their copies.
- `position.screen: "all"` (settings: Notches › Position › Screen › Every screen): a copy of the notch on every monitor, each hovered, pinned and dragged on its own. A peek shows on the focused monitor only, so changing the volume on one monitor no longer takes the notch away from the music playing on another. In bar style the notch has a copy per bar.

- Drag the notch onto another monitor: a preview shows it there, and the drop makes that monitor its home (`position.screen`; settings: Notches › Position › Screen), where the notch stays whichever monitor has focus, peeks included; a peek also shows at the top of the monitor you work on when no notch there shows it. Dropped on a workspace left out of `workspaces`, it adds that workspace, so the notch stays where it landed. Reserved space is kept on the home monitor only.
- With a vertical Omarchy bar, the bar indicator shows the compact state down the bar (the module's vertical view, or a dot) instead of hiding, and the notch drops out of the side.
- Settings window with a sidebar of pages (Notches, General, Appearance), fields grouped by section, compact style picked from picture cards, segmented choices and switches for modules.
- Settings fields can be `boolean` or `note`, live on a `page`, and show a choice as picture cards (`display: "cards"`); hosts can add pages with `hostSettingsPages`.
- Theme tokens derived from the host's colors (`muted`, `faint`, `line`, `hover`, `selected`, `surface`, `danger`, radii).
- `make check`: Node tests, QML behaviour tests, qmllint, plugin validation and offscreen visual scenarios.
- `reserveSpace` (settings: Notches › Layout › Keep windows clear): with the notch hanging in `"notch"` style, windows tile below it instead of under it. The space follows the closed notch, a sliver at rest and a compact notch's height while a module is active; peeks never move windows.
- `workspaces` (settings: Notches › Layout › Workspaces): the workspaces the closed notch, or its bar indicator, shows on. On others it moves to a screen that shows one, or hides; peeks and the open notch still show, and reserved space is only kept where the notch can hang. Hyprland only.
- `position` (settings: Notches › Position): the hanging notch on any screen edge (`edge`: top, bottom, left, right) and anywhere along it (`offset`). On a side edge peeks and the expanded notch keep their layout and the notch grows sideways; reserved space moves to that edge. In `"bar"` style the notch stays in the middle of the bar, on whichever edge the bar is.
- Hold the hanging notch for a moment and drag it to any edge (`draggable`, on by default; settings: Notches › Position › Drag to move); a quick click only pins it. It follows the nearest edge as you drag, snaps to the middle, and the drop is saved as `position`. Windows move once, when it lands. `recenter` over IPC puts it back at the top.
- Modules can give `verticalCompact` and `verticalPeek` views for a side edge; a module without a vertical compact view shows a dot there. The media and activities modules stack their compact view down the edge, and the Omarchy OSD stands its bar up.
- Settings fields can be a `number` (a slider with a fractional step, shown as a percentage with `display: "percent"`); card pictures get their option's `value`.
- README image of the notch in its four states, rendered from the real QML with `make hero`, in Omarchy's Gruvbox theme and wallpaper.

### Changed

- Modules read `notch.expanded` and `notch.peeking(module)` instead of `notch.mode` and `notch.peekModule`, since a module can show in several notches. Hosts read the place and workspaces from each notch (`service.notches`, `service.barNotch`); `NotchSurface` no longer takes a `compositor` of its own.

- The repository root is the Omarchy plugin (`manifest.json` at the root). Point `~/.config/omarchy/plugins/eryk.notchd` at the checkout instead of `hosts/omarchy`.
- The standalone host is `shell.qml` at the repository root: run `qs -p <checkout>` instead of `qs -p hosts/standalone`.
- Documentation split into README (users), `docs/` (reference), DEVELOPMENT.md and CLAUDE.md.
- Hosts tell the service which edge their bar is on (`NotchService.barEdge`) instead of `NotchSurface.barOnTop`. The Omarchy host follows the bar's position, so with a bottom or side bar the notch drops out of it.
- Picking a field's default in the settings window removes the key from the config instead of writing the default.
- The compact media view shows the track's title and artist between the artwork and the equalizer, cut short past 240 design px; the artist drops out when there is no room for it.
- The compact notch is shorter (28 design px instead of 36), close to a bar's height: tighter padding, smaller corners, and smaller media artwork and activity icon.

### Fixed

- Media artwork took a texture atlas the size of the monitor (about 25 MB) for an 80 px cover; it now gets a texture of its own, and scales down smoother.
- The default notch kept a window covering each monitor even while it showed nothing, about 25 MB of buffers; its windows now exist only while it shows a peek, and for 5 s after. A peek that needs it again after that shows about 50 ms later.
- A running timer redrew the notch four times a second; it now wakes as its clock turns, once a second, so the open notch's progress bar steps once a second too.
- Music playing cost a quarter to a third of a CPU core (on a 160 Hz monitor) and kept the compositor busy: the hidden default notch drew the media view on every monitor, and the equalizer and the progress bar never stopped easing. It now costs about 1 %: hidden copies hold no view, the equalizer and the progress bar move at 60 fps instead of the monitor's rate (8 % of a core while music plays, under 1 % of a 20-thread CPU), and a notch hidden over a fullscreen app stops its equalizer.
- The notch's animations looked choppy at their slow end: one side of the outline moved a whole pixel at a time while the other glided. It now moves in fractions of a pixel and settles on whole pixels, with its content kept on whole pixels throughout.
- Moving the pointer across the open notch's controls (the media buttons, the gear) closed and reopened it: those controls took the hover from the notch.
- With `reserveSpace`, windows took 4 s to reclaim the space after the last module ended; they now do as the notch finishes collapsing (400 ms).
- Media artwork, and its placeholder, vanished entirely under Qt's software renderer; it now shows with square corners there.

### Removed

- `scripts/build-omarchy.sh` and `dist/`: no build step is needed any more.

Earlier history is in `git log`.
