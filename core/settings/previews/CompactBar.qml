import QtQuick
import "../.."
import ".."

// Card picture for compactStyle "bar": the compact view sits in the bar.
CardPreview {
  id: preview
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
      anchors.centerIn: parent
      width: Theme.space(46)
      height: Theme.space(8)
      radius: height / 2
      color: Theme.alpha(Theme.accent, 0.35)
      border.width: 1
      border.color: Theme.accent
      Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Theme.space(4)
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.space(4); height: width; radius: width / 2
        color: preview.ink
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
  // Two windows below, untouched.
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
}
