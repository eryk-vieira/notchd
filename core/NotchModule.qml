import QtQuick

// Base type for every notch module. A module is a QML file whose root is a
// NotchModule: a built-in in core/modules/, or one a host ships (see
// NotchService.hostModules). List its id in the config's "modules" to load it.
//
// The notch shows, by state:
//   rest      nothing active: a small lip at its edge
//   compact   the highest-priority active module's `compact` view against
//             its edge (`verticalCompact` on a side edge, else a dot)
//   peek      a module's `peek` view (`verticalPeek` on a side edge, if it
//             has one), for a few seconds, after requestPeek()
//   expanded  on hover or click: the `expanded` view of every active module
//
// Views are Components so the notch can create them only while shown. They
// can refer to the module's own properties by its id. Views never rotate:
// on a side edge the notch runs down the edge for `verticalCompact` and
// `verticalPeek`, and grows sideways to hold the other views, which keep
// their layout. `notch.edge` and `notch.vertical` say where it is.
Item {
  id: module
  visible: false

  // Set by the notch when the module loads.
  property var notch: null

  // Defaults to the file name.
  property string moduleId: ""
  // Defaults to the `title` in its JSON file, else its id.
  property string title: ""

  // Higher wins the compact slot and outranks lower peeks.
  property int priority: 0

  // Whether the module has something to show in compact/expanded right now.
  property bool active: false

  // Peek even while the notch is expanded by hover (e.g. the volume OSD).
  property bool urgentPeek: false

  // Peek only on the focused screen, once: for feedback on what you just
  // did there (volume, brightness). Otherwise every notch that shows the
  // module peeks, wherever it is.
  property bool peekOnFocusedScreen: false

  // Takes typing (a text field in its expanded view): the notch's window
  // takes the keyboard while it is pinned open on it (State.keyboardFocus),
  // and Escape closes it. Hover alone never takes the keyboard; a view
  // calls requestKeyboard() (a press on its field) to pin the notch.
  property bool wantsKeyboard: false

  // Width of its expanded view, in unscaled px (Theme.space applies); the
  // default suits a list of rows.
  property int expandedWidth: 400

  property Component compact: null
  // Compact view for a side edge (left/right): narrow and tall. Without one,
  // the notch shows a dot there while the module is active.
  property Component verticalCompact: null
  property Component peek: null
  // Peek view for a side edge: narrow and tall, like a volume bar standing
  // up. Without one, `peek` shows there, the notch growing sideways.
  property Component verticalPeek: null
  property Component expanded: null

  // A setting of its own: the config's value, else the field's default.
  // The fields are declared in the JSON file next to the module's QML
  // (media.json for media.qml), with `title` and `settings` in the settings
  // schema's format and `key` relative to the module; the service reads it
  // without loading the module, so its page shows while no notch loads it.
  // Values are stored under the module's id ("resources": { "compact": "short" }).
  function setting(key) {
    return notch ? notch.moduleSetting(moduleId, key) : undefined
  }

  function requestPeek(ms) {
    if (notch) notch.requestPeek(module, ms === undefined ? 2500 : ms)
  }

  function dismissPeek() {
    if (notch) notch.dismissPeek(module)
  }

  // Pins every notch open on this module, so its window takes the keyboard
  // (wantsKeyboard) and leaving it with the pointer doesn't close it.
  function requestKeyboard() {
    if (notch) notch.requestKeyboard(module)
  }
}
