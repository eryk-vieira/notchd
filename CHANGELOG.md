# Changelog

All user-visible changes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/). The version is `manifest.json`'s. Released sections are never edited.

## [Unreleased]

### Added

- Settings window with a sidebar of pages (General, Modules, Appearance), fields grouped by section, compact style picked from picture cards, segmented choices and switches for modules.
- Settings fields can be `boolean` or `note`, live on a `page`, and show a choice as picture cards (`display: "cards"`); hosts can add pages with `hostSettingsPages`.
- Theme tokens derived from the host's colors (`muted`, `faint`, `line`, `hover`, `selected`, `surface`, `danger`, radii).
- `make check`: Node tests, QML behaviour tests, qmllint, plugin validation and offscreen visual scenarios.
- `reserveSpace` (settings: General › Layout › Keep windows clear): with the notch hanging in `"notch"` style, windows tile below it instead of under it. The space follows the closed notch, a sliver at rest and a compact notch's height while a module is active; peeks never move windows.
- `workspaces` (settings: General › Layout › Workspaces): the workspaces the closed notch, or its bar indicator, shows on. On others it moves to a screen that shows one, or hides; peeks and the open notch still show, and reserved space is only kept where the notch can hang. Hyprland only.
- README image of the notch in its four states, rendered from the real QML with `make hero`, in Omarchy's Gruvbox theme and wallpaper.

### Changed

- The repository root is the Omarchy plugin (`manifest.json` at the root). Point `~/.config/omarchy/plugins/eryk.notchd` at the checkout instead of `hosts/omarchy`.
- The standalone host is `shell.qml` at the repository root: run `qs -p <checkout>` instead of `qs -p hosts/standalone`.
- Documentation split into README (users), `docs/` (reference), DEVELOPMENT.md and CLAUDE.md.
- The compact notch is shorter (28 design px instead of 36), close to a bar's height: tighter padding, smaller corners, and smaller media artwork and activity icon.

### Fixed

- Moving the pointer across the open notch's controls (the media buttons, the gear) closed and reopened it: those controls took the hover from the notch.
- With `reserveSpace`, windows took 4 s to reclaim the space after the last module ended; they now do as the notch finishes collapsing (400 ms).
- Media artwork, and its placeholder, vanished entirely under Qt's software renderer; it now shows with square corners there.

### Removed

- `scripts/build-omarchy.sh` and `dist/`: no build step is needed any more.

Earlier history is in `git log`.
