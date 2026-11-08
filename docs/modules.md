# Writing a module

A module's logic lives in the daemon and the notch draws its **view trees** (made of primitives: [architecture.md](architecture.md#primitive-tree-v1)). There are two kinds: a **built-in** module is a Rust file in `native/notchd-modules/` ([below](#a-module-in-the-daemon)); a **user module** is a program of your own in any language, run by the daemon ([User modules](#user-modules)). No built-in module is QML any more: `native/notchd-modules/modules/` holds each one's JSON file (title, settings, defaults). A module draws with primitives only; when a view needs something they lack, the answer is a new light primitive in every UI, not QML, a canvas or a webview.

`NotchModule` is still the QML base type, for what the QML loads itself: a host's own module (the Omarchy `osd` is a `CoreModule` that only owns the IPC target, `hosts/omarchy/modules/`, importing `"../../../core"`, registered through the service's `hostModules`) and the test fixtures. Its properties are the facts every module has, so the vocabulary below (`priority`, `active`, `attention`...) is the same for the daemon's modules, which send them as the `module` message. A QML module looks like this:

```qml
import QtQuick
import ".."

NotchModule {
  id: m
  title: "Example"
  priority: 60          // higher wins the compact slot / outranks lower peeks
  active: true          // show in compact/expanded while true
  // urgentPeek: true   // peek even while expanded by hover
  // peekOnFocusedScreen: true  // peek once, on the focused screen only (feedback on what you just did there)
  // expandedWidth: 520         // its expanded view's width, unscaled px (default 400)
  // icon: String.fromCodePoint(0xF051B)  // shown closed while active with no compact view
  // attention: true           // news you haven't seen: a dot on its tab, its peek as the notch closes

  compact: Component { Text { text: "hi"; color: Theme.foreground } }
  verticalCompact: Component { Text { text: "h\ni"; color: Theme.foreground } }  // optional, for a side edge
  verticalPeek: Component { Text { text: "h\ne\ny"; color: Theme.foreground } }  // optional, for a side edge
  peek: Component { Text { text: "hello!"; color: Theme.foreground } }
  expanded: Component { Text { text: "details"; color: Theme.foreground } }

  // m.requestPeek(3000) pops the notch open with `peek` for 3 s.
  // m.openNotch() pins the first notch that shows it open, on its tab; m.closeNotch() closes them.
}
```

A module that is `active` but has no `compact` view right now leaves the closed notch at rest and still shows when expanded: the `resources` module, set to `"short"`, binds `compact` to null until a resource runs short.

The expanded view is as tall as it lays itself out; it needn't fit the screen. Past the room the notch has, the open notch scrolls its modules (the wheel, where your view doesn't take it, and a scrollbar), and in a notch with several modules (its `tabs`, on by default) it shows one module at a time, its `title` on the tab. `openNotch()` picks the module's own tab. Closed, such a notch shows every active module's `compact` view side by side, so keep it short.

Give the module an `icon` (a Nerd Font glyph, e.g. `String.fromCodePoint(0xF051B)`). While it is active with no `compact` view (the timer, stopped), the closed notch shows the icon in its place, unless the notch's `idleIcons` is off. Without an icon it stays out of the closed notch then.

A peek asked for while the notch is open (on another tab, say) doesn't show. For news that matters, set `attention: true` before `requestPeek()`: its tab gets a dot, and the peek shows once as the notch closes, unless you have seen it by then. Clear `attention` once you have (the terminal modules clear it when their view opens). The rule is `attention_peek` in `native/notchd-core/src/state.rs`.

## A module in the daemon

The timer, activities, resources, media, OSD, the agents (`claude`, `codex`) and your terminals, and every user module (a folder of `modules/` in the config dir, run by the daemon as a process), keep their logic in the daemon and send **view trees**, not QML. `core/CoreModule.qml` is the one QML type that shows them, so to the notch (tabs, compact row, peeks, the settings page) they are modules like any other:

- Its facts (`title`, `priority`, `active`, `icon`, `attention`, `urgentPeek`, `peekOnFocusedScreen`, `expandedWidth`) are the daemon's `module` message, bound as properties (`daemonOwned` is true, so the service never reports facts for it).
- Each slot (`compact`, `verticalCompact`, `peek`, `verticalPeek`, `expanded`) is a stable `Component` that draws `client.view(id, slot)` with `ViewTree`, or `null` while the daemon sends no tree for it. A press in a view goes back as the client's `event(module, slot, action, value)`.
- `NotchService` makes one for every module the daemon announces that has no QML file (`loadUrl`) and that some notch lists; a built-in has its JSON file in `native/notchd-modules/modules/`, embedded in the daemon, which gives its settings page and defaults and which the daemon lists back to the UI in `schema.modules` (no UI reads or reports it). A host module that only owns an IPC target (the Omarchy `osd`) is a `CoreModule` with the `IpcHandler` inside.

To move a module to the daemon: write `native/notchd-modules/src/<id>.rs` implementing `CoreModule` (`facts`, `view(slot, now)`, and as needed `config`, `command` for IPC, `event`, `tick`/`next_due`, `feed` for a provider's data, `take_effects` for peeks and notifications), add it to `IDS` and `create` in `lib.rs` and, if it has IPC methods, to `METHODS` in `notchd-daemon/src/corehost.rs`; add its JSON file to `native/notchd-modules/modules/` and to `INFO` in `notchd-modules/src/lib.rs` (no QML file, no UI list to edit). Settings defaults are read from that JSON file (`tree::Settings`). Test it as values in Rust (every slot builds a valid tree), and the QML behaviour with the helpers `root.ask`, `root.texts` of `tests/qml/shell.qml`. A module that needs demo data offscreen implements `demo` (the test hook `test-<id>`, only with `NOTCHD_TEST_HOOKS=1`).

A tree draws like the QML it replaced where a few general properties say so: `width`, `height`, `minWidth` (and a row's or column's `maxWidth`) fix a size, `fill` takes the rest of a row, and an `icon`'s `size` is design pixels or a text size name (`"body"`).

Icons: an `icon` (and a `button`) takes a `name`, a `glyph`, or both. `name` is a named icon the UI draws with its own symbols (`media-playback-start`, `window-close`, `list-add`...; the list is "Named icons" in `docs/architecture.md`), which is what makes a view look right on a desktop without Nerd Fonts. `glyph` is a Nerd Font codepoint (`String.fromCodePoint(0xF051B)`) and is what a UI draws when it does not know the `name`, or when you send no name. A name nobody knows is not an error, it falls back to `glyph`, so send both when you want a known look everywhere; a node with neither is invalid.

## User modules

A module of your own, in any language: a folder in the config dir whose program talks to notchd in lines of JSON. No QML, no build, no plugin API. Copy one of [the examples](examples/modules/) to start: `counter` (shell, a button), `cpu` (Python, a provider) and `greeting` (Node, settings).

```
~/.config/notchd/modules/<id>/
  module.json     the manifest
  run.sh          whatever `command` starts (any language)
```

1. `cp -r docs/examples/modules/counter ~/.config/notchd/modules/`
2. Turn it on: Settings, Notches, your notch, Loaded modules, Counter or put its id in a notch's `modules` list in the config. The daemon finds a new folder by itself; Modules lists it, with a gear to its page when its manifest has `settings`. A module no notch lists is not started.
3. Edit `run.sh` and save: the module restarts by itself (reload on save). Any file in its folder counts; hidden files, `__pycache__`, `node_modules` and `target` do not.

The [Herdr example](examples/modules/herdr/) uses the same user-module protocol to
show Herdr's agent, workspace and pane counts. It chooses when to send `peek`
and, optionally, `notify` from its own settings. Pair it with a terminal whose
command is `herdr` in a notch with `tabs: false` to put the summary above the
live Herdr interface; no built-in module is needed.

The folder name is the id: letters, digits, `-` and `_`, and not a config key or built-in id (`modules`, `position`, `theme`, `media`, `timer`...); such a folder is reported in the log and ignored.

### The manifest

```json
{
  "title": "Weather",
  "command": ["python3", "run.py", "${cache}"],
  "priority": 40,
  "icon": "",
  "expandedWidth": 360,
  "settings": [{ "key": "city", "type": "string", "label": "City", "default": "Berlin" }],
  "subscribe": ["resources"]
}
```

| Field | |
|---|---|
| `command` | required: the argv, run with the module's folder as its working directory. `${config}` and `${cache}` become folders of its own (`<config dir>/module-config/<id>` and `module-cache/<id>`), made for it. `NOTCHD_MODULE_ID` and `NOTCHD_MODULE_DIR` are in its environment |
| `title` | the tab and the settings page; the id by default |
| `priority`, `icon`, `expandedWidth`, `urgentPeek`, `peekOnFocusedScreen` | the properties of a `NotchModule` of the same name (see the top of this page) |
| `settings` | fields of its settings page, below |
| `subscribe` | providers it wants, below |
| `env` | extra environment variables (a string map; `${config}`, `${cache}` expand) |
| `permissions` | `network`, `files`, `exec`...: a note for whoever reads the manifest. Nothing is sandboxed: a module can do what you can |

### Messages

Standard input and output, one JSON object per line, UTF-8; an object with an unknown `"t"` is ignored. Standard error is the log.

From notchd:

```json
{"t":"init","proto":1,"id":"weather","config":{"city":"Berlin"},"tokens":["foreground","muted","accent"],"slots":["compact","verticalCompact","peek","verticalPeek","expanded"],"dir":"/home/you/.config/notchd/modules/weather"}
{"t":"config","config":{"city":"Paris"}}
{"t":"event","slot":"expanded","action":"refresh","value":null}
{"t":"provider","name":"resources","data":{"cpu":0.12,"mem":{"used":6500000000,"total":16000000000},"disk":{"used":300000000000,"total":500000000000,"path":"/"}}}
{"t":"stop"}
{"t":"error","code":"provider","message":"..."}
```

From the module:

```json
{"t":"set","active":true,"priority":40,"icon":"","attention":false}
{"t":"view","slot":"compact","tree":{"t":"row","gap":6,"children":[{"t":"icon","glyph":"","tone":"accent"},{"t":"text","text":"18°"}]}}
{"t":"view","slot":"expanded","tree":{"t":"column","gap":8,"children":[{"t":"text","text":"Berlin","size":"heading"},{"t":"button","label":"Refresh","action":"refresh"}]}}
{"t":"peek","ms":3000}
{"t":"notify","title":"Rain","body":"in 10 minutes"}
{"t":"open"}
{"t":"log","level":"info","text":"fetched"}
{"t":"error","message":"network down"}
{"t":"subscribe","name":"media"}
{"t":"unsubscribe","name":"media"}
```

- A module is **not shown until it sends `{"t":"set","active":true}`** and a `view` for a slot. Slots: `compact` (the closed notch), `verticalCompact`, `peek`, `verticalPeek` and `expanded`; one never sent has no view; `"tree":null` clears it.
- A `view`'s `tree` is made of the [primitives](architecture.md#primitive-tree-v1) (`row`, `column`, `text`, `icon`, `image`, `progress`, `button`, `chip`, `list`, `canvas`...; colors are `tone`s, never hex). A button's `action` comes back as an `event` with that `action` (and a `value` for a `chip` or a seeking `progress`). An invalid tree shows as an error row and the module keeps running.
- `peek` is the module's request to peek for `ms` (the rules of `requestPeek`); `open` opens the notch on it; `notify` is a desktop notification posted through `notify-send` (one a second per module; the module never takes the notification service over); `log` and standard error go to the log. `set` takes `active`, `priority`, `icon`, `attention`, `urgentPeek`, `expandedWidth`, each optional.
- You own the timer: print a `view` when something changes. At most 20 views per second per module are kept (the rest are dropped, with one warning in the log); use `progress.anchor` for a bar that moves by itself.
- The `init` line comes first. A module may ignore stdin, but it should exit on `stop`.

### Settings

`settings` uses the [settings schema's fields](settings.md#fields) (`string`, `boolean`, `integer`, `number`, `choice`, `color`...), `key` relative to the module. They appear on its page (Settings, Modules, its gear); the values are stored in notchd's config under the module's id (`"weather": { "city": "Paris" }`), and only when they differ from the `default`. The module gets them as `init.config` and, after every change, as a `config` message, always with the defaults filled in for what was never touched: it never reads the config file.

### Providers

`subscribe` in the manifest, or `{"t":"subscribe","name":"..."}` while running, sends the module `provider` messages: the latest data at once, then on change. A provider a module cannot have (anything not in this table) is answered with `{"t":"error","code":"provider"}`, and a manifest that lists one is an error row.

| Name | `data` | Sent |
|---|---|---|
| `resources` | `{cpu, mem:{used,total}, disk:{used,total,path}}`: CPU as a fraction, bytes | at most once a second; the system is read only while someone wants it |
| `media` | `{players:[{id,name,playing,title,artist,album,artUrl,length,position,canPlay,...}]}`, seconds | on change (at most 4 a second; a playing position that moves by itself is not a change) |
| `screens` | the screens as the shell reports them: names, rects, scale, focused, fullscreen, workspaces | on change |
| `usage` | `{agent:"claude"\|"codex", limits:[{id,label,percent,resetsAt,windowSecs}], stale, problem}`, one message per agent | when the agent's plan usage is read, which the `claude` and `codex` modules do while a notch lists them |

A module that does not read its input is not waited for: provider data beyond a backlog of 32 lines is dropped.

### Logs and errors

`~/.local/state/notchd/logs/<id>.log` (`$XDG_STATE_HOME`) has the module's standard error, its `log` messages and notes of the host (starts, exits), rotated at 1 MiB, five kept. Whatever goes wrong shows in the notch, where the module's views would be, as a red row with the reason, the log's path and a **Restart** button: a crash (`weather exited (1)`), a command that does not start, a bad `module.json` (with its line and column; the running module is left alone until it is fixed), an invalid view, an `error` message, no first view after 5 s. A crash restarts after 1, 2, 4... 30 s (reset after a minute up); five quick ones in a row stop it until you save a file or press Restart. A line over 1 MiB or not JSON is logged and skipped; ten in a row count as a crash. Closing the daemon sends `stop`, then SIGTERM after 1 s and SIGKILL after 3 s to the module's whole process group.

### Not yet

`cmd` (a module's own IPC method), `visible` (which slot is shown), the `peek` message's `slot`, the `audio`, `notifications` and `osd` providers, webview surfaces, and a sandbox.

## Settings

A built-in module's title, settings fields and whether it is an [agent](#agents) are in a JSON file named after it (`native/notchd-modules/modules/resources.json`, embedded in the daemon; a host's in its own folder, `hosts/omarchy/modules/osd.json`, which the host reports in `catalog`). The daemon reads it whether the module loads or not, so the module has its page in the settings window (Modules, then its gear) even while no notch shows it. `settings` uses the settings schema's format (see [settings.md](settings.md)) with `key` relative to the module; values are stored under the module's id, and the module reads them with its config: the value, else the field's default (`tree::Settings`; a QML module uses `setting(key)`). A field that names another `page` shows there, under the module's title. Without a `title`, the title is the id. A user module's `module.json` is the same format.

```json
{
  "title": "Resources",
  "settings": [
    { "key": "compact", "type": "choice", "label": "Closed notch", "default": "always",
      "options": [{ "value": "always", "label": "Always" }, { "value": "short", "label": "When running short" }] }
  ]
}
```

A module reads it as `compact` (config: `"resources": { "compact": "short" }`).

A module's settings apply to every notch, since it loads once. Pick an id that isn't a config key (`modules`, `position`, `theme`...).

## Notches without decoration

Any module can be in a notch that shows nothing at rest, the way an OSD only shows when volume or brightness changes. A notch says `"decoration": false` (Settings, Notches, its page: Show at rest):

- At rest it shows nothing: no lip, no closed row, no space kept clear, nothing to hover.
- It appears only while one of its modules peeks (or, in navigation, as a dashed outline to say where it is), and goes away when the peek ends.
- It draws over the decorated notches it overlaps on that spot while it shows (`Position.coveredByUndecorated`, the UI's geometry), which hide until it goes, and stays out of the side-by-side packing.
- With no `position.screen` it is on every connected screen; the peek shows on the copy on the focused screen, like any notch on several screens.
- Navigation lists it like any notch: numbered, moved, opened in Settings, removed.

A host can declare notches that exist without any config (`defaultNotches` in its `catalog`): the Omarchy host declares one with `osd`, undecorated, top center. A declared notch exists unless the config's `removedNotches` lists its id (removing it, in navigation or Settings, writes that); moving it or changing its modules writes an entry in `notches` with its `id` and only what differs. Give a module meant for such a notch a `peek` view (and a `verticalPeek` for a side edge).

## Typing

The notch's window takes the keyboard while it is pinned open, whatever it shows: a click on the notch, `toggleNotch <id>` from a shortcut, navigation, or a module calling `requestKeyboard()`, which pins every notch open on it. A module with a text field calls it when the field is pressed, since a notch opened by hover has no keyboard. Hover alone never takes the keyboard from the window you are typing in. The window asks for it exclusively, the only way a layer gets it without a click, and on demand once it has it, so a focus or workspace shortcut can still move to a window; the notch then closes, as a click away does. On a monitor without focus it stays exclusive, since Hyprland gives an on-demand layer's keyboard there straight back to the focused monitor; Escape closes it. Escape and Ctrl+Escape close the notch: a field leaves Escape alone and it goes up to the card; a terminal keeps Escape and lets Ctrl+Escape out. The rules are `keyboard_focus` and `keyboard_change` in `native/notchd-core/src/state.rs`; the UI sends `focus` and the daemon answers with each copy's `keyboard`.

```qml
expanded: Component {
  TextInput {
    focus: true
    TapHandler { onTapped: m.requestKeyboard() }
  }
}
```

## Agents

A coding agent (`claude`, `codex`) is a module of the daemon (`native/notchd-modules/src/{claude,codex}.rs`, over `term.rs`) that runs the agent's own terminal UI, **in the daemon**: the program is a PTY the daemon owns, so it keeps running while the notch is closed, while the shell reloads (`make restart`) and whatever the UI does; the expanded view only attaches a terminal view to it ([architecture.md](architecture.md#free-surface-tier-3)). It has `"agent"` in its JSON file. Notches show it like any module; the Modules page lists agents apart, under Agents. Adding one takes three things:

- `modules/<id>.json`: its title and `"agent": { "command": "<its command>" }`. That brings the fields every agent has (`settings::agent_settings`): `directory`, `command` (the command is its default), `idleMinutes`, `width`, `height`, `font`. `"usage": "<source>"` there (`claude`, `codex`) adds its plan usage, below, and the fields `usage` and `usageWarn`. `agent.help` adds a sentence to a field's help, by key, for what only that agent needs said; a field of its own in `settings` with the same key replaces the inherited one.
- `native/notchd-modules/src/<id>.rs`: a `Kind` for `term::TermModule` (its name, the function that reads its terminal title to `{ working, title }`, its default command, the logo file if it has one, the usage source), added to `IDS` and `create` in `lib.rs`, and to `METHODS` in `notchd-daemon/src/corehost.rs` for its own IPC word.
- Its title parser in `native/notchd-core/src/agent.rs` (`claude_title`, `codex_title`), with cases in `tests/vectors/rules/agent.json`: the closed notch's title and working dot come from the title the agent gives the terminal.

```json
{
  "title": "Codex",
  "agent": {
    "command": "codex",
    "help": { "idleMinutes": "Codex takes 500 to 700 MB, besides its shared background server." }
  }
}
```

A terminal of your own needs no file: each entry of the config's `terminals` (`"<id>": { "command", "title" }`, `config::terminals`) is a module of the daemon (`terminal.rs`) that runs the command as a shell script, starts in your home without a `directory` and shows the terminal's title as it is (`terminal::plain_title`). Its info is made from the entry (`settings::terminal_info`): its title, the entry's own `title` and `command` as fields with `absolute` keys (`terminals.<id>.command`, `required`), then the fields every agent has but `command`, under its id. So the id is a config key: one the config already has (`config::RESERVED_KEYS`, a host's settings keys) or a module's is skipped with a warning in the log, as is an id with anything but letters, digits, `-` and `_`. The Modules page lists them under Terminals, where Add terminal makes one (`config::with_terminal_added`: a free id, your shell) and the trash can removes one with its settings and its place in every notch (`config::without_terminal`); over IPC, `terminal <id> <command>` reaches them. A terminal that leaves the config, or that no notch lists, stops its program.

An agent with `usage` shows its plan's limits under its header: a bar per window (5 hours, the week, a model's week), how much is used and when it resets (`plan.rs`, rules in `notchd-core/src/usage.rs`). The daemon asks the endpoint the agent's own CLI calls (Claude's `api/oauth/usage`, Codex's `backend-api/wham/usage`, with `curl` on a thread of its own) with the login the CLI keeps (`~/.claude/.credentials.json`, `~/.codex/auth.json`, or under `CLAUDE_CONFIG_DIR`, `CODEX_HOME`): every 5 minutes, when the agent finishes a task (at most once a minute), and, while the login is missing or lapsed, every 5 seconds by looking at its file (no request until it has changed). That login is only read, never refreshed or written; when it lapses, the last limits stay, faint, with why, until the agent renews it by running. A 429 leaves it alone for at least 5 minutes. A limit that passes `usageWarn` (80 % by default) peeks once in its window, and again when it is reached; the first answer after a start is taken as seen, so a restart doesn't warn again. Offscreen (`scripts/isolated.sh` sets `NOTCHD_OFFLINE=1`, which the daemon reads) nothing asks the network or reads a login; the tests' and the renders' limits come from the module's test hook (`notchd ipc test-claude usage <json>`, with `NOTCHD_TEST_HOOKS=1`; also `title <text> [attention]` and `peek <ms>`).

Without a `directory`, an agent starts in notchd's own folder, `notchd` in your documents folder (`xdg-user-dir DOCUMENTS`, else `~/Documents`), made the first time (`terminal::OWN_DIR`); `/resume` in Claude Code and Codex lists the sessions of the folder they start in, so it is always the same one. The program starts the first time a view of it opens, and goes on while the notch is closed (unless `idleMinutes` says to stop it: a closed, idle agent stops, and the next view starts a new one); the restart button starts a new one. The daemon emulates the terminal (Ghostty's libghostty-vt) and the UI draws the screen it sends ([architecture.md](architecture.md#terminals-the-grid)): the kitty keyboard protocol and images, the mouse for programs that ask for it, selection (Shift over a program that has the mouse), Ctrl+Shift+C and Ctrl+Shift+V, your theme's colors. A UI says in its `hello` that it draws terminals (GNOME draws them directly in the Shell); without one, the view says so, and `ask` answers `no UI connected draws a terminal`. It takes every key, Escape included, except Ctrl+Escape, which closes the notch and leaves the program running (`Terminal.isLeaveKey`); so does the header's button. Over IPC, `agent <id> <command>` reaches it by its id ([ipc.md](ipc.md#agents)), whatever notch shows it.

## The scope rule

A module **shows** state, it does not **own** it. A notifications module mirrors toasts; it does not register as the notification server. The one exception today is the Omarchy `osd` module, which takes the `osd` IPC target from the stock OSD plugin (and says so in its README).

## Rules

- Sizes go through `Theme.space(px)` and text through `Theme.font.*`, so the module follows the host's density and fonts.
- Colors come from the theme tokens (`Theme.foreground`, `Theme.muted`, `Theme.line`, …), never hard-coded or ad-hoc alphas. See [theming.md](theming.md).
- Views are Components that size themselves through `implicitWidth`/`implicitHeight`; the notch springs to fit. Expanded views get a fixed width: 400 px, or the module's `expandedWidth`.
- (QML modules only) `notch` (set by the service) is the `NotchService`; read state from it, never from another module's internals. A module may show in several notches at once, so the service answers for all of them: `notch.expanded` (some notch is open) and `notch.peeking(module)` (some notch shows that module's peek). Each notch picks the vertical views on a side edge itself.
- Views never rotate. On a side edge the notch runs down the edge for `verticalCompact` and `verticalPeek`; `peek` (for a module without a `verticalPeek`) and `expanded` keep their layout and the notch grows sideways to hold them. Give a side-edge view when a module has something narrow to show: the built-ins stack artwork over the equalizer (media), an icon over a progress bar (activities), each short resource's icon over its number (resources), and stand the OSD's bar up.
- Every change on screen redraws the notch's whole window, at the monitor's refresh rate while something moves. Don't animate without pause: a `Behavior` that never settles, or a timer of a few hundred ms easing into each value, keeps the window drawing frames for as long as it runs. Cap such a view at 60 fps with one `Timer` (interval 16) that moves it, as media's equalizer and progress bar do, instead of letting it run at the monitor's rate (160 Hz and up), and stop its timer while the view is hidden (`running: … && visible`): a notch concealed over a fullscreen app hides its card. An `Image` lands in the scene graph's texture atlas, which is sized to the window and the window covers the screen: the first one costs ~25 MB however small it is. Set `mipmap: true` on images, which keeps them out of it (media's artwork does). `make bench` measures what a view costs.

## Which view shows when

| Property | Used when |
|---|---|
| `compact` | the module is the highest-priority active one with a compact view |
| `verticalCompact` | as `compact`, with the notch on a side edge, and in a vertical bar: narrow and tall. Without one the notch shows a dot there |
| `verticalPeek` | as `peek`, on a side edge: narrow and tall. Without one, `peek` shows there |
| `peek` | the module called `requestPeek(ms)` and won: a pinned notch never peeks, hover only lets `urgentPeek` modules through, and a peek on screen is not cut short by a lower-priority one. It shows in every notch that lists the module (on the focused monitor for a notch on every monitor), and at the top of the focused monitor when no notch with the module is there. With `peekOnFocusedScreen` it shows once, on the focused monitor only: in the first notch there that lists the module, else at the top. A notch without decoration shows its peek on the copy on the focused monitor (see [Notches without decoration](#notches-without-decoration)) |
| `expanded` | the notch is expanded and the module is active; every active module's view stacks, highest priority first |

The daemon decides which view shows (`native/notchd-core/src/state.rs` and `peek.rs`, tested in Rust and by the QML scenarios in `tests/qml/scenarios.qml`): modules report their facts (active, priority, which views they have, attention) and their `requestPeek`/`dismissPeek` to it, and the UI shows what its `state` says.

## Loading

The config's `modules` (each notch's, in a config with `notches`) lists ids in order; the service loads every module some notch lists, once. An id resolves to a host module first, then a daemon module (built-in or a user's). An unknown id, or a file whose root is not a `NotchModule`, is skipped with a warning in the log.

