import QtQuick
import qs.Commons
import "../../core"

// Omarchy host: the notch overlay. Finds the service, then hands the core
// surface Omarchy's bar size (the service knows its edge); the Hyprland
// adapter comes with the service.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // Injected by the shell when the service is up; looked up otherwise.
  property var service: null

  Timer {
    interval: 200
    repeat: true
    running: !root.service && !!root.shell
    onTriggered: root.service = root.shell.serviceFor("eryk.notchd")
  }

  // The shell calls these when the overlay is summoned/hidden.
  function open() { if (root.service) root.service.open() }
  function close() { if (root.service) root.service.close() }

  readonly property var bar: root.shell ? root.shell.bar : null

  NotchSurface {
    svc: root.service
    layerNamespace: "eryk-notchd"
    barHeight: {
      var size = root.bar ? Math.max(0, Number(root.bar.barSize) || 0) : 0
      if (size > 0) return size
      var vertical = !!root.bar && (root.bar.position === "left" || root.bar.position === "right")
      return vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
    }
    barHidden: !!(root.bar && root.bar.barHidden)
  }
}
