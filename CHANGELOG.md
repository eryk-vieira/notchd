# Changelog

All user-visible changes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/). The version is `manifest.json`'s. Released sections are never edited.

## [Unreleased]

### Added

- With a vertical Omarchy bar, the bar indicator shows the compact state down the bar (the module's vertical view, or a dot) instead of hiding, and the notch drops out of the side.
- Settings window with a sidebar of pages (General, Modules, Appearance), fields grouped by section, compact style picked from picture cards, segmented choices and switches for modules.
- Settings fields can be `boolean` or `note`, live on a `page`, and show a choice as picture cards (`display: "cards"`); hosts can add pages with `hostSettingsPages`.
- Theme tokens derived from the host's colors (`muted`, `faint`, `line`, `hover`, `selected`, `surface`, `danger`, radii).
- `make check`: Node tests, QML behaviour tests, qmllint, plugin validation and offscreen visual scenarios.
- `reserveSpace` (settings: General › Layout › Keep windows clear): with the notch hanging in `"notch"` style, windows tile below it instead of under it. The space follows the closed notch, a sliver at rest and a compact notch's height while a module is active; peeks never move windows.
- `workspaces` (settings: General › Layout › Workspaces): the workspaces the closed notch, or its bar indicator, shows on. On others it moves to a screen that shows one, or hides; peeks and the open notch still show, and reserved space is only kept where the notch can hang. Hyprland only.
- `position` (settings: General › Position): the hanging notch on any screen edge (`edge`: top, bottom, left, right) and anywhere along it (`offset`). On a side edge peeks and the expanded notch keep their layout and the notch grows sideways; reserved space moves to that edge. In `"bar"` style the notch stays in the middle of the bar, on whichever edge the bar is.
- Hold the hanging notch for a moment and drag it to any edge (`draggable`, on by default; settings: General › Position › Drag to move); a quick click only pins it. It follows the nearest edge as you drag, snaps to the middle, and the drop is saved as `position`. Windows move once, when it lands. `recenter` over IPC puts it back at the top.
- Modules can give `verticalCompact` and `verticalPeek` views for a side edge, and read `notch.edge` and `notch.vertical`; a module without a vertical compact view shows a dot there. The media and activities modules stack their compact view down the edge, and the Omarchy OSD stands its bar up.
- Settings fields can be a `number` (a slider with a fractional step, shown as a percentage with `display: "percent"`); card pictures get their option's `value`.
- README image of the notch in its four states, rendered from the real QML with `make hero`, in Omarchy's Gruvbox theme and wallpaper.

### Changed

- The repository root is the Omarchy plugin (`manifest.json` at the root). Point `~/.config/omarchy/plugins/eryk.notchd` at the checkout instead of `hosts/omarchy`.
- The standalone host is `shell.qml` at the repository root: run `qs -p <checkout>` instead of `qs -p hosts/standalone`.
- Documentation split into README (users), `docs/` (reference), DEVELOPMENT.md and CLAUDE.md.
- Hosts tell the service which edge their bar is on (`NotchService.barEdge`) instead of `NotchSurface.barOnTop`. The Omarchy host follows the bar's position, so with a bottom or side bar the notch drops out of it.
- Picking a field's default in the settings window removes the key from the config instead of writing the default.
- The compact media view shows the track's title and artist between the artwork and the equalizer, cut short past 240 design px; the artist drops out when there is no room for it.
- The compact notch is shorter (28 design px instead of 36), close to a bar's height: tighter padding, smaller corners, and smaller media artwork and activity icon.

### Fixed

- The notch's animations looked choppy at their slow end: one side of the outline moved a whole pixel at a time while the other glided. It now moves in fractions of a pixel and settles on whole pixels, with its content kept on whole pixels throughout.
- Moving the pointer across the open notch's controls (the media buttons, the gear) closed and reopened it: those controls took the hover from the notch.
- With `reserveSpace`, windows took 4 s to reclaim the space after the last module ended; they now do as the notch finishes collapsing (400 ms).
- Media artwork, and its placeholder, vanished entirely under Qt's software renderer; it now shows with square corners there.

### Removed

- `scripts/build-omarchy.sh` and `dist/`: no build step is needed any more.

Earlier history is in `git log`.
