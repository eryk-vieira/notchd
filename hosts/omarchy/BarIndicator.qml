import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// The compact state of the notch in bar style (NotchService.barNotch; one
// notch at most): its highest-priority active module's `barView` (or its
// `compact`); in a vertical bar its `verticalCompact`, or a dot. That notch
// has a copy on every monitor; hovering this indicator drops the copy on
// this monitor out of the bar, clicking pins it. Takes no space while
// nothing is active, with no notch in bar style, or while this monitor shows
// a workspace the notch doesn't hang on.
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

  readonly property var notch: root.svc ? root.svc.barNotch : null
  readonly property var module: root.notch ? root.notch.compactModule : null
  readonly property Component view: !root.module ? null
    : root.vertical ? (root.module.verticalCompact || dotView) : (root.module.barView || root.module.compact)
  readonly property var barScreen: root.QsWindow.window ? root.QsWindow.window.screen : null
  readonly property bool shown: root.view !== null && root.notch.showsOn(root.barScreen)
  readonly property string screenName: root.barScreen ? String(root.barScreen.name) : ""
  // The notch's copy on this monitor.
  readonly property var copy: root.notch ? root.notch.copyOn(root.screenName) : null

  // Across a horizontal bar, down a vertical one.
  visible: shown
  implicitWidth: !shown ? 0 : root.vertical ? barSize : content.implicitWidth + Style.space(12)
  implicitHeight: !shown ? 0 : root.vertical ? content.implicitHeight + Style.space(12) : barSize

  // A vertical bar, for a module without a `verticalCompact`.
  Component {
    id: dotView
    Item {
      implicitWidth: Style.space(6)
      implicitHeight: Style.space(6)
      Rectangle { anchors.fill: parent; radius: width / 2; color: Color.accent }
    }
  }

  Loader {
    id: content
    anchors.centerIn: parent
    sourceComponent: root.view
  }

  // The copy's hover; it also has the notch card's.
  HoverHandler {
    id: hover
    onHoveredChanged: if (root.copy) root.copy.setPointer("bar", hovered, root.screenName)
  }
  // A copy that changes (the notch left bar style and came back) never
  // keeps a pointer this bar no longer reports.
  onCopyChanged: if (root.copy && hover.hovered) root.copy.setPointer("bar", true, root.screenName)

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: if (root.copy) root.copy.togglePinned(root.screenName)
  }
}
