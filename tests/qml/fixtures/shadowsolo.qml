import QtQuick
import "../core"

// The module of the undecorated notch the shadow test declares (`solo`).
NotchModule {
  id: m
  title: "Solo"
  peek: Component { Rectangle { implicitWidth: 120; implicitHeight: 30; color: "gray" } }
  expanded: Component { Rectangle { implicitHeight: 40; color: "gray" } }
}
