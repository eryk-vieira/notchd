# Changelog

All user-visible changes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/). The version is `manifest.json`'s. Released sections are never edited.

## [Unreleased]

### Added

- Settings window with a sidebar of pages (General, Modules, Appearance), fields grouped by section, compact style picked from picture cards, segmented choices and switches for modules.
- Settings fields can be `boolean` or `note`, live on a `page`, and show a choice as picture cards (`display: "cards"`); hosts can add pages with `hostSettingsPages`.
- Theme tokens derived from the host's colors (`muted`, `faint`, `line`, `hover`, `selected`, `surface`, `danger`, radii).
- `make check`: Node tests, qmllint, plugin validation and offscreen visual scenarios.

### Changed

- The repository root is the Omarchy plugin (`manifest.json` at the root). Point `~/.config/omarchy/plugins/eryk.notchd` at the checkout instead of `hosts/omarchy`.
- The standalone host is `shell.qml` at the repository root: run `qs -p <checkout>` instead of `qs -p hosts/standalone`.
- Documentation split into README (users), `docs/` (reference), DEVELOPMENT.md and CLAUDE.md.

### Removed

- `scripts/build-omarchy.sh` and `dist/`: no build step is needed any more.

Earlier history is in `git log`.
