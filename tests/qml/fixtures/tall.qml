import QtQuick
import "../core"

// A module whose expanded view is taller than the room the tests give the
// card, for the scrolling and tabs tests; and a compact view.
NotchModule {
  id: m
  title: "Tall"
  active: true
  expandedWidth: 300
  compact: Component { Rectangle { implicitWidth: 80; implicitHeight: 12; color: "gray" } }
  expanded: Component {
    Rectangle {
      implicitHeight: 900
      color: "gray"
    }
  }
}
