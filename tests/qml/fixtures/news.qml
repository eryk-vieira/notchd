import QtQuick
import "../core"

// A module with a compact view and a peek, for the tabs tests: what the
// closed notch shows of each module, and a peek of news you haven't seen.
NotchModule {
  id: m
  title: "News"
  active: true
  compact: Component { Rectangle { implicitWidth: 60; implicitHeight: 12; color: "gray" } }
  peek: Component { Rectangle { implicitWidth: 200; implicitHeight: 40; color: "gray" } }
  expanded: Component { Rectangle { implicitHeight: 40; color: "gray" } }
}
