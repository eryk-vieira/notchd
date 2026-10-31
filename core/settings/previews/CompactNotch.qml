import QtQuick
import "../.."

// Card picture for compactStyle "notch": a pill hangs under the top edge.
Item {
  id: preview
  property bool selected: false
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
  // The notch: square on top (it hangs from the bar), round at the bottom,
  // drawn over the windows.
  Item {
    anchors.top: bar.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    width: Theme.space(58)
    height: Theme.space(14)
    clip: true
    Rectangle {
      y: -radius
      width: parent.width
      height: parent.height + radius
      radius: Theme.space(7)
      color: Theme.background
      border.width: 1
      border.color: Theme.accent
    }
    Row {
      anchors.centerIn: parent
      spacing: Theme.space(4)
      Rectangle { width: Theme.space(5); height: width; radius: width / 2; color: preview.ink; anchors.verticalCenter: parent.verticalCenter }
      Rectangle { width: Theme.space(26); height: Theme.space(3); radius: height / 2; color: preview.ink; anchors.verticalCenter: parent.verticalCenter }
    }
  }
}
