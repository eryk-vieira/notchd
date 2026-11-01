import QtQuick
import QtQuick.Layouts
import ".."

// `string` and `color` fields. A color adds a swatch and is validated.
// Emptying the field removes the key, so the default comes back; for a
// `required` one, emptying it is refused, as a bad color is.
RowLayout {
  id: control

  property var field: ({})
  property var value
  // The raw config value: undefined while the key is absent, so the input
  // shows the default as a placeholder instead of as text.
  property var stored
  signal edited(var value)

  readonly property bool isColor: field.type === "color"
  property bool invalid: false

  spacing: Theme.space(8)

  function commit() {
    var t = input.text.trim()
    if (t === "") {
      control.invalid = !!control.field.required
      if (!control.invalid) control.edited(undefined)
      return
    }
    if (control.isColor && !/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t)) {
      control.invalid = true
      return
    }
    control.invalid = false
    control.edited(t)
  }

  Rectangle {
    visible: control.isColor
    Layout.preferredWidth: Theme.space(32)
    Layout.preferredHeight: Theme.space(32)
    radius: Theme.radiusSmall
    border.width: 1
    border.color: Theme.line
    color: control.value !== undefined ? control.value : "transparent"
  }

  Rectangle {
    Layout.preferredWidth: Theme.space(220)
    Layout.preferredHeight: Theme.space(32)
    radius: Theme.radiusSmall
    color: Theme.alpha(Theme.background, 0.5)
    border.width: 1
    border.color: control.invalid ? Theme.danger : (input.activeFocus ? Theme.accent : Theme.line)

    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: Theme.space(10)
      anchors.rightMargin: Theme.space(10)
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      text: control.stored === undefined ? "" : String(control.stored)
      color: Theme.foreground
      selectionColor: Theme.alpha(Theme.accent, 0.4)
      font.family: Theme.font.family
      font.pixelSize: Theme.font.bodySmall
      selectByMouse: true
      onEditingFinished: control.commit()
      Keys.onEscapePressed: function(event) { input.focus = false; event.accepted = true }

      Label {
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === "" && !input.activeFocus
        wrapMode: Text.NoWrap
        text: control.field["default"] !== undefined ? String(control.field["default"]) + " (default)" : "default"
        color: Theme.faint
        font.pixelSize: Theme.font.bodySmall
      }
    }
  }
}
