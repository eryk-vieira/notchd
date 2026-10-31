# Settings window

`core/settings/SettingsWindow.qml`. An ordinary toplevel window with a fixed size, so tiling compositors float it, and it takes keyboard input, which the notch overlay never does. Every change goes through `NotchService.setConfigValue`: it applies at once and is written to the config file shortly after.

## Fields

The window is generated from `NotchService.settingsSchema`: the core's fields, then the host's `hostSettingsSchema`. Each field is an object:

| Key | |
|---|---|
| `key` | config key; dotted for nested objects (`theme.accent`) |
| `type` | `choice`, `integer`, `number`, `boolean`, `string`, `color`, `modules`, `workspaces`, `notches`, `moduleCatalog` or `note` (text only, no key) |
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
| `notches` | `NotchCatalog`: a row per notch, where it is and what it shows (`Settings.notchSummary`), with a gear to its page, a trash can (with more than one) and Add, which opens the new notch's page; it edits the list through the service (`addNotch`, `removeNotch`) |
| `moduleCatalog` | `ModuleCatalog`: every module the host can load, where it shows (`Settings.moduleStatus`) and a gear to its page; no key, edits nothing |
| `note` | none; just the title and help |

## Several notches

The Notches page (`notch`) lists the notches. Each one's gear opens its page, `notch/<index>` (`Settings.notchPageId`), which holds every field for its own keys: name, modules, position, workspaces... Showing that page sets `NotchService.settingsNotch`, the notch the window edits. Those fields take that notch's key: `position.edge` at the top level, `notches.1.position.edge` in a list, with the top-level value it inherits as the field's default. Picking that value removes the notch's own key, so it inherits again. The General page has what applies to every notch: the hover delays and, unless they name another page, the host's fields. In Omarchy, the gear next to a notch in the bar button's panel opens the window on that notch's page.

## Modules

The Modules page lists every module the host can load (`availableModuleIds`), with where it shows: on or off with one notch, the notches that list it with several, standalone (or standalone and off) for a [standalone module](modules.md#standalone-modules), whose page starts with its Enabled switch and position. Which modules a notch shows stays on each notch's page, since it is the notch's own key. A module with settings of its own has a gear that opens its page, `modules/<id>` (`Settings.modulePageId`), with its fields, keys under its id (`Settings.moduleFields`); a field that names another page goes there, under the module's title. The fields come from the module's JSON file ([modules.md](modules.md#settings)), read without loading it, so a module no notch shows can be set up before it is switched on.

## Pages

`NotchService.settingsPages`: the core's (General, Notches, Modules, Appearance), then the host's `hostSettingsPages`, each `{ id, label, icon }` with `icon` a Nerd Font code point, then a page per notch and per module. A host page with a core page's id replaces its label or icon. A page with no fields is hidden. A page whose id has a `/` is a sub-page of the part before it (`notch/1` of `notch`, `modules/media` of `modules`): it has no sidebar entry, the sidebar marks its parent while it shows, a link above its fields leads back, and so does Escape. A sub-page that goes away (its notch removed) falls back to its parent. The page shown is kept on the service, so it survives closing the window; it starts on General.

## Card pictures

An option's `preview` is the url of a QML file whose root is a `CardPreview` (`core/settings/CardPreview.qml`). Draw it with theme colors; its `selected` property follows the card and `value` is its option's value, so one file can draw every option. The pictures in `core/settings/previews/` are examples; `Edge.qml` draws all four edges.

## Adding a control

Every control takes `field` (the schema entry) and `value` (the config value, or the default while the key is absent) and emits `edited(value)`; `undefined` removes the key, and `SettingRow` turns the field's default into `undefined` (`Settings.storedValue`), so the config never stores a default. `SettingRow.qml` picks the control by type: add the component there, and to the tables above. Controls that need the width of the page (cards, lists) go under the title instead of beside it; `SettingRow.wide` decides.

## Layout of the code

| File | |
|---|---|
| `SettingsWindow.qml` | window, sidebar, page content |
| `Settings.js` | pages and sub-pages, sections, module files and pages, notch summaries, list edits and slider steps; pure, tested in `tests/settings.test.mjs` |
| `SettingRow.qml` | one field: text and the control for its type |
| `Label.qml`, `Icon.qml`, `Button.qml`, `IconButton.qml`, `NavItem.qml`, `ListRow.qml` | building blocks; `ListRow` is a row of the Notches and Modules lists |
| `*Control.qml`, `CardChoice.qml`, `Toggle.qml`, `ModuleList.qml`, `ModuleCatalog.qml`, `NotchCatalog.qml`, `WorkspaceChips.qml` | the controls |
