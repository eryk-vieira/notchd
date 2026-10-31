import QtQuick
import QtQuick.Layouts
import ".."

// `choice` field with `display: "cards"`: one card per option, each with a
// picture of what it does. An option's `preview` is the url of a QML file
// whose root takes `selected`; options without one show just the label.
Flow {
  id: control

  property var field: ({})
  property var value
  signal edited(var value)

  spacing: Theme.space(12)

  Repeater {
    model: control.field.options || []
    delegate: Rectangle {
      id: card
      required property var modelData
      readonly property bool isSelected: control.value === modelData.value

      width: Theme.space(176)
      height: column.implicitHeight + Theme.space(16)
      radius: Theme.radius
      color: area.containsMouse && !isSelected ? Theme.hover : "transparent"
      border.width: isSelected ? 2 : 1
      border.color: isSelected ? Theme.accent : (area.containsMouse ? Theme.faint : "transparent")

      ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.space(8)
        spacing: Theme.space(8)

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Theme.space(92)
          radius: Theme.radiusSmall
          color: Theme.mix(Theme.background, Theme.foreground, 0.02)
          border.width: 1
          border.color: Theme.line
          clip: true
          Loader {
            anchors.fill: parent
            anchors.margins: 1
            active: !!card.modelData.preview
            source: card.modelData.preview || ""
            onLoaded: item.selected = Qt.binding(function() { return card.isSelected })
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: Theme.space(4)
          spacing: Theme.space(6)
          Label {
            text: card.modelData.label || String(card.modelData.value)
            wrapMode: Text.NoWrap
            color: card.isSelected ? Theme.foreground : Theme.muted
          }
          Icon {
            visible: card.isSelected
            glyph: 0xF012C  // nf-md-check
            size: Theme.font.body
            color: Theme.foreground
          }
          Item { Layout.fillWidth: true }
        }
      }

      MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.edited(card.modelData.value)
      }
    }
  }
}
