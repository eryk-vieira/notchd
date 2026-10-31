import QtQuick

// Base type for every notch module. A module is a file in modules/ whose root
// is a NotchModule; list its file name (without .qml) in config.json to load it.
//
// The notch shows, by state:
//   rest      nothing active: a small lip under the clock (hidden in bar style)
//   compact   the highest-priority active module's `compact` view under the
//             clock, or its `barView` in the bar (compactStyle "bar")
//   peek      a module's `peek` view, for a few seconds, after requestPeek()
//   expanded  on hover or click: the `expanded` view of every active module
//
// Views are Components so the notch can create them only while shown. They
// can refer to the module's own properties by its id.
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

  property Component compact: null
  // Compact view sized for the bar strip (compactStyle "bar"); falls back to
  // `compact` when unset.
  property Component barView: null
  property Component peek: null
  property Component expanded: null

  function requestPeek(ms) {
    if (notch) notch.requestPeek(module, ms === undefined ? 2500 : ms)
  }

  function dismissPeek() {
    if (notch) notch.dismissPeek(module)
  }
}
