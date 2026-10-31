# Development entry points. `make check` is the gate: run it before every
# commit. See DEVELOPMENT.md.

QMLLINT ?= $(firstword $(wildcard /usr/lib/qt6/bin/qmllint /usr/lib64/qt6/bin/qmllint) \
	$(shell command -v qmllint6 2>/dev/null) $(shell command -v qmllint 2>/dev/null))

# The Omarchy host imports qs.Commons/qs.Ui, which only exist inside the
# Omarchy shell, so lint skips it; `make restart` and the shell log cover it.
LINT_FILES = shell.qml core/*.qml core/settings/*.qml core/settings/previews/*.qml \
	core/modules/*.qml

# Dev config for `make dev`, so it never touches ~/.config/notchd.
DEV_CONFIG ?= $(CURDIR)/build/dev-config.json

.PHONY: check test qmltest visual hero icons bench lint validate dev restart clean

check: test qmltest lint validate visual

# Node tests of the pure-JS rules (core/*.js, core/settings/*.js).
test:
	node --test tests/*.test.mjs

# QML behaviour tests (tests/qml/shell.qml), offscreen: bindings, signals
# and animations the Node tests can't reach. Regression tests live here.
qmltest:
	scripts/qml-test.sh

# Renders the settings window offscreen into build/visual/; fails on any QML
# warning, so it also proves the core loads.
visual:
	scripts/visual-test.sh

# The README image, docs/images/hero.webp: the real notch offscreen, with a
# demo media player on a private D-Bus, over Omarchy's Gruvbox wallpaper
# (WALLPAPER=<image> for another). Rerun after a visual change to the notch
# and commit the image.
hero:
	scripts/hero.sh

# The app icon at every hicolor size, plus notchd.ico, from
# assets/icons/hicolor/scalable/apps/notchd.svg. Rerun after editing the SVG
# and commit the PNGs.
icons:
	scripts/icons.sh

# What notchd costs (CPU, wakeups, memory) per scenario, on your real
# Wayland session with a demo player on a private D-Bus; a second notch
# shows while it runs. Not part of `check`: it needs a display and the
# numbers depend on the machine. Report in build/bench.md.
bench:
	scripts/bench.sh

# --unqualified disable: delegates read outer ids by design.
# The filtered line is a qmllint false positive: it ignores a qmldir without
# a `module` line when linting the singleton itself.
lint:
	@test -x "$(QMLLINT)" || { echo "Qt 6 qmllint not found" >&2; exit 1; }
	@out=$$("$(QMLLINT)" --unqualified disable $(LINT_FILES) 2>&1 \
	  | grep -v 'Type Theme not declared as singleton in qmldir'); \
	if printf '%s\n' "$$out" | grep -qE '^(Warning|Error)'; then \
	  printf '%s\n' "$$out"; exit 1; fi; \
	echo "qmllint: clean"

# The repo root is the Omarchy plugin.
validate:
	omarchy plugin validate .

# The standalone host (shell.qml) against a scratch config; hot-reloads.
dev:
	@mkdir -p build
	NOTCHD_CONFIG="$(DEV_CONFIG)" quickshell -p .

# The Omarchy shell does not hot-reload plugin QML.
restart:
	omarchy restart shell

clean:
	rm -rf build
