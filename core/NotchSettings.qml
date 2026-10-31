import QtQuick
import QtQuick.Layouts
import Quickshell

// The settings window: a form generated from NotchService.settingsSchema.
// Every change applies at once and is written back to the config file (see
// NotchService.setConfigValue), so there is no Apply button. It is an
// ordinary toplevel window, so it works on any compositor and takes keyboard
// input, which the notch overlay never does.
FloatingWindow {
  id: win

  property var svc: null

  title: "notchd settings"
  color: Theme.background

  readonly property int pad: Theme.space(22)
  readonly property int labelWidth: Theme.space(150)
  implicitWidth: Theme.space(500)
  implicitHeight: Math.min(form.implicitHeight + win.pad * 2, Theme.space(760))
  // A fixed size, so tiling compositors float it like a dialog.
  minimumSize: Qt.size(win.implicitWidth, win.implicitHeight)
  maximumSize: Qt.size(win.implicitWidth, win.implicitHeight)

  onClosed: if (win.svc) win.svc.closeSettings()

  readonly property color fg: Theme.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.18)
  readonly property color accent: Theme.accent
  readonly property color danger: "#e06c75"

  function valueOf(field) {
    var v = win.svc ? win.svc.configValue(field.key) : undefined
    return v === undefined ? field["default"] : v
  }
  function setValue(field, value) {
    if (win.svc) win.svc.setConfigValue(field.key, value)
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: if (win.svc) win.svc.closeSettings()

    Flickable {
      anchors.fill: parent
      contentHeight: form.implicitHeight + win.pad * 2
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      ColumnLayout {
        id: form
        x: win.pad
        y: win.pad
        width: win.width - win.pad * 2
        spacing: Theme.space(14)

        // ---------------------------------------------------------- header
        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            text: "notchd"
            color: win.fg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.heading
            font.bold: true
          }
          Text {
            text: "esc to close"
            color: win.dim
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
        }

        // ---------------------------------------------------------- fields
        Repeater {
          model: win.svc ? win.svc.settingsSchema : []

          delegate: ColumnLayout {
            id: row
            required property var modelData
            required property int index
            readonly property var field: modelData
            readonly property bool newSection: index === 0
              || win.svc.settingsSchema[index - 1].section !== field.section

            Layout.fillWidth: true
            spacing: Theme.space(6)

            Text {
              visible: row.newSection && !!row.field.section
              Layout.topMargin: row.index === 0 ? 0 : Theme.space(10)
              text: String(row.field.section || "").toUpperCase()
              color: win.dim
              font.family: Theme.font.family
              font.pixelSize: Theme.font.caption
              font.letterSpacing: 1
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Theme.space(12)

              Text {
                Layout.preferredWidth: win.labelWidth
                Layout.alignment: Qt.AlignTop
                topPadding: Theme.space(4)
                text: row.field.label || row.field.key
                color: win.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                wrapMode: Text.Wrap
              }

              Loader {
                Layout.fillWidth: true
                sourceComponent: {
                  switch (row.field.type) {
                    case "choice": return choiceControl
                    case "integer": return sliderControl
                    case "color": return textControl
                    case "string": return textControl
                    case "modules": return modulesControl
                    default: return unknownControl
                  }
                }
              }
            }

            Text {
              visible: !!row.field.help
              Layout.fillWidth: true
              Layout.leftMargin: win.labelWidth + Theme.space(12)
              text: row.field.help || ""
              color: win.dim
              font.family: Theme.font.family
              font.pixelSize: Theme.font.caption
              wrapMode: Text.Wrap
            }

            // ------------------------------------------------- controls
            // Declared per row so they can read `row.field`.

            Component {
              id: unknownControl
              Text {
                text: "unsupported field type: " + row.field.type
                color: win.danger
                font.family: Theme.font.family
                font.pixelSize: Theme.font.caption
              }
            }

            // Segmented buttons, one per option.
            Component {
              id: choiceControl
              Row {
                spacing: 0
                Repeater {
                  model: row.field.options || []
                  delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool selected: win.valueOf(row.field) === modelData.value
                    width: optionText.implicitWidth + Theme.space(24)
                    height: Theme.space(28)
                    radius: Theme.space(6)
                    color: selected ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.22)
                      : (optionArea.containsMouse ? win.faint : "transparent")
                    border.width: 1
                    border.color: selected ? win.accent : win.line
                    Text {
                      id: optionText
                      anchors.centerIn: parent
                      text: modelData.label || modelData.value
                      color: selected ? win.fg : win.dim
                      font.family: Theme.font.family
                      font.pixelSize: Theme.font.bodySmall
                    }
                    MouseArea {
                      id: optionArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: win.setValue(row.field, modelData.value)
                    }
                  }
                }
              }
            }

            // Slider for integers, snapped to `step`.
            Component {
              id: sliderControl
              RowLayout {
                id: slider
                spacing: Theme.space(12)
                readonly property real min: Number(row.field.min || 0)
                readonly property real max: Number(row.field.max === undefined ? 100 : row.field.max)
                readonly property real step: Math.max(1, Number(row.field.step || 1))
                readonly property real value: Number(win.valueOf(row.field)) || 0
                readonly property real fraction: slider.max > slider.min
                  ? Math.max(0, Math.min(1, (slider.value - slider.min) / (slider.max - slider.min))) : 0

                function setFromX(x, width) {
                  var f = Math.max(0, Math.min(1, x / Math.max(1, width)))
                  var v = slider.min + f * (slider.max - slider.min)
                  v = Math.round(v / slider.step) * slider.step
                  v = Math.max(slider.min, Math.min(slider.max, v))
                  if (v !== slider.value) win.setValue(row.field, v)
                }

                Item {
                  Layout.fillWidth: true
                  implicitHeight: Theme.space(28)
                  Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: Theme.space(4)
                    radius: height / 2
                    color: win.line
                    Rectangle {
                      width: parent.width * slider.fraction
                      height: parent.height
                      radius: parent.radius
                      color: win.accent
                    }
                  }
                  Rectangle {
                    x: track.width * slider.fraction - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.space(14)
                    height: width
                    radius: width / 2
                    color: win.fg
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: function(mouse) { slider.setFromX(mouse.x, width) }
                    onPositionChanged: function(mouse) { if (pressed) slider.setFromX(mouse.x, width) }
                  }
                }
                Text {
                  Layout.preferredWidth: Theme.space(64)
                  horizontalAlignment: Text.AlignRight
                  text: slider.value + (row.field.unit ? " " + row.field.unit : "")
                  color: win.fg
                  font.family: Theme.font.family
                  font.pixelSize: Theme.font.bodySmall
                }
              }
            }

            // Text field; "color" adds a swatch and validation. Emptying it
            // removes the key, so the default comes back.
            Component {
              id: textControl
              RowLayout {
                id: textRow
                spacing: Theme.space(8)
                readonly property bool isColor: row.field.type === "color"
                readonly property var stored: win.svc ? win.svc.configValue(row.field.key) : undefined
                property bool invalid: false

                function commit() {
                  var t = input.text.trim()
                  if (t === "") { textRow.invalid = false; win.setValue(row.field, undefined); return }
                  if (textRow.isColor && !/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t)) {
                    textRow.invalid = true
                    return
                  }
                  textRow.invalid = false
                  win.setValue(row.field, t)
                }

                Rectangle {
                  visible: textRow.isColor
                  Layout.preferredWidth: Theme.space(28)
                  Layout.preferredHeight: Theme.space(28)
                  radius: Theme.space(6)
                  border.width: 1
                  border.color: win.line
                  color: textRow.stored !== undefined ? textRow.stored
                    : (row.field["default"] !== undefined ? row.field["default"] : "transparent")
                }
                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Theme.space(28)
                  radius: Theme.space(6)
                  color: win.faint
                  border.width: 1
                  border.color: textRow.invalid ? win.danger : (input.activeFocus ? win.accent : win.line)
                  TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space(10)
                    anchors.rightMargin: Theme.space(10)
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    text: textRow.stored === undefined ? "" : String(textRow.stored)
                    color: win.fg
                    selectionColor: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.4)
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.bodySmall
                    selectByMouse: true
                    onEditingFinished: textRow.commit()
                    Keys.onEscapePressed: function(event) { input.focus = false; event.accepted = true }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      visible: input.text === "" && !input.activeFocus
                      text: row.field["default"] !== undefined ? String(row.field["default"]) + " (default)" : "default"
                      color: win.dim
                      font: input.font
                    }
                  }
                }
              }
            }

            // Module list: check to load, arrows to reorder the loaded ones.
            Component {
              id: modulesControl
              Column {
                id: modulesList
                spacing: Theme.space(4)
                readonly property var enabledIds: {
                  var v = win.valueOf(row.field)
                  return Array.isArray(v) ? v.map(String) : []
                }
                readonly property var all: {
                  var out = modulesList.enabledIds.slice()
                  var avail = win.svc ? win.svc.availableModuleIds : []
                  for (var i = 0; i < avail.length; i++)
                    if (out.indexOf(avail[i]) === -1) out.push(avail[i])
                  return out
                }

                function toggle(id) {
                  var next = modulesList.enabledIds.slice()
                  var at = next.indexOf(id)
                  if (at === -1) next.push(id)
                  else next.splice(at, 1)
                  win.setValue(row.field, next)
                }
                function move(id, delta) {
                  var next = modulesList.enabledIds.slice()
                  var at = next.indexOf(id)
                  var to = at + delta
                  if (at === -1 || to < 0 || to >= next.length) return
                  next.splice(at, 1)
                  next.splice(to, 0, id)
                  win.setValue(row.field, next)
                }

                Repeater {
                  model: modulesList.all
                  delegate: Rectangle {
                    id: moduleRow
                    required property string modelData
                    readonly property int position: modulesList.enabledIds.indexOf(modelData)
                    readonly property bool isOn: position !== -1
                    readonly property bool known: !win.svc || win.svc.availableModuleIds.indexOf(modelData) !== -1
                    width: modulesList.width
                    height: Theme.space(30)
                    radius: Theme.space(6)
                    color: rowArea.containsMouse ? win.faint : "transparent"

                    MouseArea {
                      id: rowArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: modulesList.toggle(moduleRow.modelData)
                    }

                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: Theme.space(6)
                      anchors.rightMargin: Theme.space(4)
                      spacing: Theme.space(10)

                      Rectangle {
                        Layout.preferredWidth: Theme.space(16)
                        Layout.preferredHeight: Theme.space(16)
                        radius: Theme.space(4)
                        color: moduleRow.isOn ? win.accent : "transparent"
                        border.width: 1
                        border.color: moduleRow.isOn ? win.accent : win.line
                        Text {
                          anchors.centerIn: parent
                          visible: moduleRow.isOn
                          text: "✓"
                          color: Theme.background
                          font.pixelSize: Theme.font.caption
                          font.bold: true
                        }
                      }
                      Text {
                        Layout.fillWidth: true
                        text: moduleRow.modelData + (moduleRow.known ? "" : "  (not found)")
                        color: moduleRow.known ? (moduleRow.isOn ? win.fg : win.dim) : win.danger
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.bodySmall
                      }
                      Repeater {
                        model: moduleRow.isOn ? [-1, 1] : []
                        delegate: Text {
                          required property int modelData
                          readonly property bool usable: modelData < 0 ? moduleRow.position > 0
                            : moduleRow.position < modulesList.enabledIds.length - 1
                          text: modelData < 0 ? "↑" : "↓"
                          color: usable ? (arrowArea.containsMouse ? win.fg : win.dim) : win.line
                          font.family: Theme.font.family
                          font.pixelSize: Theme.font.body
                          MouseArea {
                            id: arrowArea
                            anchors.fill: parent
                            anchors.margins: -Theme.space(4)
                            hoverEnabled: true
                            enabled: parent.usable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modulesList.move(moduleRow.modelData, parent.modelData)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // ---------------------------------------------------------- footer
        Text {
          Layout.fillWidth: true
          Layout.topMargin: Theme.space(8)
          text: "Changes apply live and save to " + (win.svc ? win.svc.configPath : "")
          color: win.dim
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
          wrapMode: Text.WrapAnywhere
        }
      }
    }
  }
}
