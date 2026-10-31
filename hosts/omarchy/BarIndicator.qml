import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// The notch's compact state inside the bar (compactStyle "bar"): the
// highest-priority active module's `barView` (or its `compact`). Hovering it
// drops the notch out from under the bar on this monitor; clicking pins it.
// Takes no space while nothing is active, in "notch" style, or while this
// monitor shows a workspace the notch doesn't hang on.
BarWidget {
  id: root
  moduleName: "eryk.notchd"

  property var svc: null
  Timer {
    interval: 200
    repeat: true
    triggeredOnStart: true
    running: !root.svc && !!root.bar && !!root.bar.shell
    onTriggered: root.svc = root.bar.shell.serviceFor("eryk.notchd")
  }

  readonly property var module: root.svc && root.svc.compactStyle === "bar" ? root.svc.compactModule : null
  readonly property Component view: root.module ? (root.module.barView || root.module.compact) : null
  readonly property var barScreen: root.QsWindow.window ? root.QsWindow.window.screen : null
  readonly property bool shown: root.view !== null && !root.vertical && root.svc.showsOn(root.barScreen)

  // One pointer source per bar (there is a bar per monitor).
  readonly property string pointerKey: "bar:" + root.screenName
  readonly property string screenName: root.barScreen ? String(root.barScreen.name) : ""

  visible: shown
  implicitWidth: shown ? content.implicitWidth + Style.space(12) : 0
  implicitHeight: barSize

  Loader {
    id: content
    anchors.centerIn: parent
    sourceComponent: root.view
  }

  HoverHandler {
    onHoveredChanged: if (root.svc) root.svc.setPointer(root.pointerKey, hovered, root.screenName)
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: if (root.svc) root.svc.togglePinned(root.screenName)
  }
}
