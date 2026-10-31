import QtQuick
import "../.."
import ".."

// Card picture for a `position.edge` option (its `value`): a screen with the
// bar on top and the notch hanging from that edge.
CardPreview {
  id: preview
  readonly property string edge: String(preview.value || "top")
  readonly property bool vertical: preview.edge === "left" || preview.edge === "right"
  readonly property color ink: preview.selected ? Theme.foreground : Theme.muted

  Rectangle {
    id: bar
    width: parent.width
    height: Theme.space(14)
    color: Theme.alpha(Theme.foreground, 0.08)
    Row {
      anchors.left: parent.left
      anchors.leftMargin: Theme.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.space(3)
      Repeater {
        model: 3
        Rectangle { width: Theme.space(5); height: width; radius: width / 2; color: Theme.faint }
      }
    }
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: Theme.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Theme.space(18); height: Theme.space(3); radius: height / 2
      color: Theme.faint
    }
  }
  Row {
    anchors.top: bar.bottom
    anchors.topMargin: Theme.space(6)
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Theme.space(6)
    Repeater {
      model: 2
      Rectangle {
        width: (preview.width - Theme.space(24)) / 2
        height: preview.height - bar.height - Theme.space(12)
        radius: Theme.space(3)
        color: "transparent"
        border.width: 1
        border.color: Theme.line
      }
    }
  }

  // The notch: square against its edge, round on the open side, centered
  // on the stretch of the edge the bar leaves free.
  Item {
    id: notch
    readonly property real length: Theme.space(preview.vertical ? 40 : 58)
    readonly property real depth: Theme.space(14)
    readonly property real r: Theme.space(7)
    width: preview.vertical ? notch.depth : notch.length
    height: preview.vertical ? notch.length : notch.depth
    x: preview.edge === "left" ? 0 : preview.edge === "right" ? preview.width - width : (preview.width - width) / 2
    y: preview.edge === "top" ? bar.height
      : preview.edge === "bottom" ? preview.height - height
      : bar.height + (preview.height - bar.height - height) / 2
    clip: true
    // Oversized on the edge side so only the open side's corners round.
    Rectangle {
      x: preview.edge === "left" ? -notch.r : 0
      y: preview.edge === "top" ? -notch.r : 0
      width: notch.width + (preview.vertical ? notch.r : 0)
      height: notch.height + (preview.vertical ? 0 : notch.r)
      radius: notch.r
      color: Theme.background
      border.width: 1
      border.color: preview.selected ? Theme.accent : Theme.faint
    }
    Rectangle {
      anchors.centerIn: parent
      width: Theme.space(5); height: width; radius: width / 2
      color: preview.ink
    }
  }
}
