# Settings window

`core/settings/SettingsWindow.qml`. An ordinary toplevel window with a fixed size, so tiling compositors float it, and it takes keyboard input, which the notch overlay never does. Every change goes through `NotchService.setConfigValue`: it applies at once and is written to the config file shortly after.

## Fields

The window is generated from `NotchService.settingsSchema`: the core's fields, then the host's `hostSettingsSchema`. Each field is an object:

| Key | |
|---|---|
| `key` | config key; dotted for nested objects (`theme.accent`) |
| `type` | `choice`, `integer`, `number`, `boolean`, `string`, `color`, `modules`, `workspaces`, `notches` or `note` (text only, no key) |
| `label`, `help` | title and description |
| `page` | sidebar page id; `general` when absent |
| `section` | heading the field sits under, within its page; sections keep the order their first field appears in |
| `default` | value shown while the key is absent; picking it removes the key |
| `options` | `[{ value, label, preview }]`, for `choice` |
| `display` | `"cards"` shows a `choice` as picture cards instead of segments; `"percent"` shows a 0..1 `number` as 0 to 100 % |
| `min`, `max`, `step`, `unit` | for `integer` and `number` (a slider; a `number`'s step may be a fraction) |

| Type | Control |
|---|---|
| `choice` | `SegmentedControl`, or `CardChoice` with `display: "cards"` |
| `integer`, `number` | `SliderControl` |
| `boolean` | `Toggle` |
| `string`, `color` | `TextControl` (a color adds a swatch and is validated) |
| `modules` | `ModuleList` |
| `workspaces` | `WorkspaceChips`: 1 to 10, the compositor's workspaces and the picked ones; none picked removes the key |
| `notches` | `NotchPicker`: a chip per notch, to pick the one the window edits, and Add/Remove; it edits the list through the service (`addNotch`, `removeNotch`) |
| `note` | none; just the title and help |

## Several notches

The window edits one notch at a time, `NotchService.settingsNotch` (its index), picked at the top of the General and Modules pages. The core's fields for a notch's own keys (modules, compact style, position, workspaces...) take that notch's key: `position.edge` at the top level, `notches.1.position.edge` in a list, with the top-level value it inherits as the field's default. Picking that value removes the notch's own key, so it inherits again. The hover delays and the host's fields apply to every notch. The gear in an expanded notch opens the window on that notch.

## Pages

`NotchService.settingsPages`: the core's (General, Modules, Appearance), then the host's `hostSettingsPages`, each `{ id, label, icon }` with `icon` a Nerd Font code point. A host page with a core page's id replaces its label or icon. A page with no fields is hidden. The page shown is kept on the service, so it survives closing the window.

## Card pictures

An option's `preview` is the url of a QML file whose root is a `CardPreview` (`core/settings/CardPreview.qml`). Draw it with theme colors; its `selected` property follows the card and `value` is its option's value, so one file can draw every option. The pictures in `core/settings/previews/` are examples; `Edge.qml` draws all four edges.

## Adding a control

Every control takes `field` (the schema entry) and `value` (the config value, or the default while the key is absent) and emits `edited(value)`; `undefined` removes the key, and `SettingRow` turns the field's default into `undefined` (`Settings.storedValue`), so the config never stores a default. `SettingRow.qml` picks the control by type: add the component there, and to the tables above. Controls that need the width of the page (cards, lists) go under the title instead of beside it; `SettingRow.wide` decides.

## Layout of the code

| File | |
|---|---|
| `SettingsWindow.qml` | window, sidebar, page content |
| `Settings.js` | pages, sections, list edits and slider steps; pure, tested in `tests/settings.test.mjs` |
| `SettingRow.qml` | one field: text and the control for its type |
| `Label.qml`, `Icon.qml`, `Button.qml`, `NavItem.qml` | building blocks |
| `*Control.qml`, `CardChoice.qml`, `Toggle.qml`, `ModuleList.qml`, `WorkspaceChips.qml` | the controls |
