import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "Settings.js" as Settings

// The settings window: a sidebar of pages and, for the current page, its
// fields grouped by section. Built from NotchService.settingsPages and
// settingsSchema; every change applies at once and is written back to the
// config file (NotchService.setConfigValue), so there is no Apply button.
//
// An ordinary toplevel window, so it works on any compositor and takes
// keyboard input, which the notch overlay never does.
FloatingWindow {
  id: win

  property var svc: null
  // The page's scroller (the visual tests scroll it to reach lower fields).
  readonly property alias pageView: flick

  title: "notchd settings"
  color: Theme.background

  implicitWidth: Theme.space(780)
  implicitHeight: Theme.space(540)
  // A fixed size, so tiling compositors float it like a dialog.
  minimumSize: Qt.size(win.implicitWidth, win.implicitHeight)
  maximumSize: Qt.size(win.implicitWidth, win.implicitHeight)

  onClosed: if (win.svc) win.svc.closeSettings()

  // ----------------------------------------------------------------- pages
  // Settings.js has the rules.
  readonly property var schema: win.svc ? win.svc.settingsSchema : []
  readonly property var pages: Settings.visiblePages(win.svc ? win.svc.settingsPages : [], win.schema)
  readonly property string currentPage: Settings.resolvePage(win.pages, win.svc ? win.svc.settingsPage : "")
  readonly property var sections: Settings.sections(win.schema, win.currentPage)

  function showPage(id) { if (win.svc) win.svc.settingsPage = id }
  function cyclePage(delta) { win.showPage(Settings.cyclePage(win.pages, win.currentPage, delta)) }

  // Opens the config file, or its folder while the file doesn't exist yet.
  Process {
    id: openConfig
    command: ["sh", "-c", "[ -e \"$1\" ] && exec xdg-open \"$1\"; d=$(dirname \"$1\"); mkdir -p \"$d\" && exec xdg-open \"$d\"",
              "sh", win.svc ? win.svc.configPath : ""]
  }

  // ---------------------------------------------------------------- layout
  // Painted here as well as on the window, so grabs (tests/visual) match.
  Rectangle {
    anchors.fill: parent
    color: Theme.background
    focus: true
    Keys.onEscapePressed: if (win.svc) win.svc.closeSettings()
    Keys.onPressed: function(event) {
      if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
        win.cyclePage(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
        event.accepted = true
      }
    }

    RowLayout {
      anchors.fill: parent
      spacing: 0

      // ------------------------------------------------------------ sidebar
      Rectangle {
        Layout.fillHeight: true
        Layout.preferredWidth: Theme.space(210)
        color: Theme.surface

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Theme.space(14)
          spacing: Theme.space(4)

          Label {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space(10)
            Layout.topMargin: Theme.space(8)
            Layout.bottomMargin: Theme.space(14)
            role: "title"
            text: "Settings"
          }

          Repeater {
            model: win.pages
            delegate: NavItem {
              required property var modelData
              Layout.fillWidth: true
              icon: modelData.icon
              label: modelData.label
              current: modelData.id === win.currentPage
              onActivated: win.showPage(modelData.id)
            }
          }

          Item { Layout.fillHeight: true }

          Button {
            Layout.fillWidth: true
            icon: 0xF0214  // nf-md-file
            text: "Open config file"
            onClicked: openConfig.running = true
          }
          Label {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space(4)
            Layout.leftMargin: Theme.space(2)
            role: "help"
            color: Theme.faint
            font.pixelSize: Theme.font.caption
            wrapMode: Text.WrapAnywhere
            text: win.svc ? win.svc.configPath.replace(/^\/home\/[^\/]+/, "~") : ""
          }
        }
      }

      Rectangle {
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        color: Theme.line
      }

      // ------------------------------------------------------------ content
      Flickable {
        id: flick
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentHeight: content.implicitHeight + Theme.space(56)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Connections {
          target: win
          function onCurrentPageChanged() { flick.contentY = 0 }
        }

        ColumnLayout {
          id: content
          x: Theme.space(32)
          y: Theme.space(28)
          width: flick.width - Theme.space(64)
          spacing: Theme.space(30)

          Repeater {
            model: win.sections
            delegate: ColumnLayout {
              id: section
              required property var modelData
              Layout.fillWidth: true
              spacing: Theme.space(16)

              Label {
                visible: section.modelData.name !== ""
                Layout.fillWidth: true
                role: "section"
                text: section.modelData.name
              }

              Repeater {
                model: section.modelData.fields
                delegate: ColumnLayout {
                  id: entry
                  required property var modelData
                  required property int index
                  Layout.fillWidth: true
                  spacing: Theme.space(16)

                  Rectangle {
                    visible: entry.index > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.line
                  }
                  SettingRow {
                    Layout.fillWidth: true
                    field: entry.modelData
                    svc: win.svc
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
