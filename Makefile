# Development entry points. `make check` is the gate: run it before every
# commit. See DEVELOPMENT.md.

QMLLINT ?= $(firstword $(wildcard /usr/lib/qt6/bin/qmllint /usr/lib64/qt6/bin/qmllint) \
	$(shell command -v qmllint6 2>/dev/null) $(shell command -v qmllint 2>/dev/null))

# The Omarchy host imports qs.Commons/qs.Ui, which only exist inside the
# Omarchy shell, so lint skips it; `make restart` and the shell log cover it.
LINT_FILES = shell.qml core/*.qml core/settings/*.qml core/settings/previews/*.qml \
	core/modules/*.qml
# Not core/terminal/: it imports QMLTermWidget, whose package ships no type
# information for qmllint. The QML tests load it where it is installed.

# Dev config for `make dev`, so it never touches ~/.config/notchd.
DEV_CONFIG ?= $(CURDIR)/build/dev-config.json

.PHONY: check test qmltest visual hero icons shaders bench lint validate dev restart deps avatar-deps live-deps clean

check: test qmltest lint validate visual

# Node tests of the pure-JS rules (core/*.js, core/settings/*.js), the
# avatar pipeline's tests that need no models (skipped without NumPy and
# Pillow) and the live bridge's that need no GStreamer.
test:
	node --test tests/*.test.mjs
	python3 tests/make_avatar_test.py
	python3 tests/codex_live_test.py

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

# Shaders: core/avatar/avatar.frag into the .qsb Qt loads, committed (the
# plugin has no build step). Rerun after editing the .frag; lint checks the
# .qsb is current.
QSB ?= $(firstword $(wildcard /usr/lib/qt6/bin/qsb /usr/lib64/qt6/bin/qsb) $(shell command -v qsb 2>/dev/null))
SHADERS = core/avatar/avatar.frag
shaders:
	@test -x "$(QSB)" || { echo "Qt 6 qsb not found (qt6-shadertools)" >&2; exit 1; }
	@for f in $(SHADERS); do "$(QSB)" --qt6 -o "$$f.qsb" "$$f" && echo "$$f.qsb"; done

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
	@if test -x "$(QSB)"; then \
	  tmp=$$(mktemp); for f in $(SHADERS); do \
	    "$(QSB)" --qt6 -o "$$tmp" "$$f" >/dev/null && cmp -s "$$tmp" "$$f.qsb" \
	      || { rm -f "$$tmp"; echo "$$f.qsb is stale or broken: make shaders" >&2; exit 1; }; \
	  done; rm -f "$$tmp"; echo "shaders: current"; \
	else echo "qsb not found: shaders not checked" >&2; fi
	@python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' core/avatar/make-avatar.py \
	  && echo "make-avatar.py: parses"
	@python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' core/live/codex-live.py \
	  && echo "codex-live.py: parses"

# The repo root is the Omarchy plugin.
validate:
	omarchy plugin validate .

# The standalone host (shell.qml) against a scratch config; hot-reloads.
dev:
	@mkdir -p build
	NOTCHD_CONFIG="$(DEV_CONFIG)" quickshell -p .

# The Omarchy shell does not hot-reload plugin QML. Installs the optional
# packages first (deps).
restart: deps
	omarchy restart shell

# Optional packages the modules use: qmltermwidget, the codex module's
# terminal. Installed with pacman only when missing (sudo asks then); without
# pacman, says what to install.
OPTIONAL_PACKAGES = qmltermwidget
deps:
	@for pkg in $(OPTIONAL_PACKAGES); do \
	  if ! command -v pacman >/dev/null 2>&1; then \
	    echo "notchd: install $$pkg with your package manager for the codex module" >&2; \
	  elif ! pacman -Q "$$pkg" >/dev/null 2>&1; then \
	    echo "notchd: installing $$pkg (the codex module's terminal)"; \
	    sudo pacman -S --needed --noconfirm "$$pkg"; \
	  fi; \
	done

# What an agent's avatar needs to be made from a photo (core/avatar/
# make-avatar.py). Not part of deps: python-mediapipe pulls in
# python-tensorflow, about 1.5 GB in all, so only those who want an avatar
# install it. python-mediapipe comes from the Omarchy repository.
AVATAR_PACKAGES = python-numpy python-pillow python-onnxruntime-cpu python-mediapipe
avatar-deps:
	@if ! command -v pacman >/dev/null 2>&1; then \
	  echo "notchd: install $(AVATAR_PACKAGES) (or their equivalents) for avatars" >&2; exit 1; fi
	@missing=; for pkg in $(AVATAR_PACKAGES); do pacman -Q "$$pkg" >/dev/null 2>&1 || missing="$$missing $$pkg"; done; \
	if [ -z "$$missing" ]; then echo "notchd: the avatar's packages are installed"; \
	else echo "notchd: installing$$missing (agents' avatars; python-mediapipe brings python-tensorflow, ~1.5 GB in all)"; \
	  sudo pacman -S --needed$$missing; fi

# What a spoken conversation (the codex-live module, core/live/codex-live.py)
# needs: GStreamer's WebRTC (gst-plugins-bad, libnice), Opus over RTP
# (gst-plugins-good) and the microphone and speakers through pipewire-pulse
# (pulsesrc, pulsesink), Python's GObject.
# About 8 MB; not part of deps, as only that module uses them.
LIVE_PACKAGES = python-gobject gst-plugins-base gst-plugins-good gst-plugins-bad libnice libpulse
live-deps:
	@if ! command -v pacman >/dev/null 2>&1; then \
	  echo "notchd: install $(LIVE_PACKAGES) (or their equivalents) for Codex Live" >&2; exit 1; fi
	@missing=; for pkg in $(LIVE_PACKAGES); do pacman -Q "$$pkg" >/dev/null 2>&1 || missing="$$missing $$pkg"; done; \
	if [ -z "$$missing" ]; then echo "notchd: Codex Live's packages are installed"; \
	else echo "notchd: installing$$missing (Codex Live: WebRTC and the microphone)"; \
	  sudo pacman -S --needed$$missing; fi

clean:
	rm -rf build
