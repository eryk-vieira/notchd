import QtQuick

// Base type for every notch module. A module is a QML file whose root is a
// NotchModule: a built-in in core/modules/, or one a host ships (see
// NotchService.hostModules). List its id in the config's "modules" to load it.
//
// The notch shows, by state:
//   rest      nothing active: a small lip at its edge (hidden in bar style)
//   compact   the highest-priority active module's `compact` view against
//             its edge (`verticalCompact` on a side edge, else a dot), or its
//             `barView` in the host's bar (compactStyle "bar")
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

  property Component compact: null
  // Compact view sized for the bar strip (compactStyle "bar"); falls back to
  // `compact` when unset.
  property Component barView: null
  // Compact view for a side edge (left/right): narrow and tall. Without one,
  // the notch shows a dot there while the module is active.
  property Component verticalCompact: null
  property Component peek: null
  // Peek view for a side edge: narrow and tall, like a volume bar standing
  // up. Without one, `peek` shows there, the notch growing sideways.
  property Component verticalPeek: null
  property Component expanded: null

  function requestPeek(ms) {
    if (notch) notch.requestPeek(module, ms === undefined ? 2500 : ms)
  }

  function dismissPeek() {
    if (notch) notch.dismissPeek(module)
  }
}
