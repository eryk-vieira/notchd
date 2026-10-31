import QtQuick
import QtQuick.Layouts
import Quickshell
import "core"

// The README image (docs/images/hero.png): the real NotchCard in four
// states, each driven by its own NotchService with demo data, over a mock
// desktop. scripts/hero.sh runs it offscreen on a private D-Bus with
// demo-player.py, so the media module shows a fictional track.
ShellRoot {
  id: root

  readonly property string outDir: Quickshell.env("NOTCHD_VISUAL_DIR")
  readonly property string outFile: Quickshell.env("NOTCHD_HERO_FILE") || (root.outDir + "/hero.png")

  // Rendered at 2x so it stays sharp on high-density screens.
  readonly property var palette: ({
    foreground: "#c8cbd4", background: "#121318", accent: "#8fbfa8",
    fontFamily: "JetBrainsMono Nerd Font", spacingScale: 2,
    fontCaption: 20, fontBodySmall: 22, fontBody: 24, fontHeading: 32, fontDisplay: 64
  })
  Component.onCompleted: Theme.provider = root.palette

  component Service: NotchService {
    property string tag: ""
    ipcTarget: "notchd-hero-" + tag
    configPath: root.outDir + "/hero-" + tag + ".json"
    barStyleAvailable: false
  }
  Service { id: compactSvc; tag: "compact"; defaultModules: ["media"] }
  Service { id: activitySvc; tag: "activity"; defaultModules: ["activities"] }
  Service {
    id: osdSvc; tag: "osd"; defaultModules: ["osd"]
    hostModules: ({ osd: Qt.resolvedUrl("hosts/omarchy/modules/osd.qml") })
  }
  Service { id: expandedSvc; tag: "expanded"; defaultModules: ["media", "activities"] }

  // A slice of a desktop: wallpaper, a bar, and the notch hanging from it.
  component Screen: Rectangle {
    id: screen
    property var svc: null
    readonly property int barHeight: Theme.space(26)

    radius: Theme.space(14)
    clip: true
    border.width: 1
    border.color: Theme.line
    gradient: Gradient {
      GradientStop { position: 0.0; color: "#2a2f45" }
      GradientStop { position: 0.55; color: "#3d3354" }
      GradientStop { position: 1.0; color: "#6b4a5e" }
    }
    // A soft glow, so the wallpaper isn't flat.
    Rectangle {
      width: screen.width * 0.9; height: width; radius: width / 2
      x: screen.width * 0.45; y: screen.height * 0.25
      color: Theme.alpha("#e8a26b", 0.16)
    }

    Rectangle {
      id: bar
      width: parent.width
      height: screen.barHeight
      color: Theme.background
      Row {
        anchors.left: parent.left
        anchors.leftMargin: Theme.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space(9)
        Repeater {
          model: ["1", "2", "3", "4"]
          Text {
            required property string modelData
            required property int index
            text: modelData
            color: index === 0 ? Theme.foreground : Theme.faint
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
        }
      }
      Text {
        anchors.centerIn: parent
        text: "Saturday 11:49"
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: Theme.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: "󰖩  󰕾  󰁹"
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
      }
    }

    NotchCard {
      svc: screen.svc
      maxWidth: screen.width - Theme.space(24)
      x: Math.round((screen.width - width) / 2)
      y: screen.barHeight
    }
  }

  component Caption: ColumnLayout {
    property string title: ""
    property string detail: ""
    spacing: Theme.space(2)
    Text {
      text: parent.title
      color: Theme.foreground
      font.family: Theme.font.family
      font.pixelSize: Theme.font.body
      font.bold: true
    }
    Text {
      Layout.fillWidth: true
      text: parent.detail
      wrapMode: Text.Wrap
      color: Theme.muted
      font.family: Theme.font.family
      font.pixelSize: Theme.font.bodySmall
    }
  }

  FloatingWindow {
    id: win
    implicitWidth: scene.width
    implicitHeight: scene.height
    color: Theme.background

    Rectangle {
      id: scene
      readonly property int pad: Theme.space(40)
      readonly property int gap: Theme.space(20)
      width: Theme.space(1000)
      height: column.implicitHeight + pad * 2
      color: "#0d0e12"

      ColumnLayout {
        id: column
        x: scene.pad
        y: scene.pad
        width: scene.width - scene.pad * 2
        spacing: scene.gap

        ColumnLayout {
          Layout.bottomMargin: Theme.space(8)
          spacing: Theme.space(6)
          Text {
            text: "notchd"
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.display
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            text: "A dynamic notch for Wayland, built with Quickshell. It hangs from the top edge and shows what your system is doing: media, volume, script activities, or any module you write."
            wrapMode: Text.Wrap
            color: Theme.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: scene.gap
          Repeater {
            model: [
              { svc: compactSvc, title: "Compact", detail: "Something is active: a sliver hangs from the bar." },
              { svc: activitySvc, title: "Peek", detail: "A script pushes an activity; it pops open for a moment." },
              { svc: osdSvc, title: "OSD", detail: "Volume and brightness, in place of the stock OSD." }
            ]
            ColumnLayout {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: Theme.space(10)
              Screen {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.space(150)
                svc: parent.modelData.svc
              }
              Caption { Layout.fillWidth: true; title: parent.modelData.title; detail: parent.modelData.detail }
            }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Theme.space(10)
          Screen {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.space(290)
            svc: expandedSvc
          }
          Caption {
            Layout.fillWidth: true
            title: "Expanded"
            detail: "Hover or click: every active module at once, with its controls. The gear opens the settings."
          }
        }
      }
    }
  }

  // Let modules load and the media track arrive (and its peek pass), set
  // each state, let the springs settle, grab.
  Timer {
    interval: 1500; running: true
    onTriggered: {
      activitySvc.moduleById("activities").push(JSON.stringify({
        id: "deploy", icon: "󰜎", title: "Deploying api", subtitle: "staging · 3 of 5",
        progress: 64, duration: 600000 }))
      osdSvc.moduleById("osd").show(JSON.stringify({ icon: "volume", value: "62", duration: "600000" }))
      expandedSvc.moduleById("activities").push(JSON.stringify({
        id: "build", icon: "󰒓", title: "Building notchd", subtitle: "make check",
        progress: 80, sticky: true, peek: false }))
      expandedSvc.open()
      grabTimer.start()
    }
  }
  Timer {
    id: grabTimer
    interval: 4500
    onTriggered: {
      compactSvc.dismissPeek()
      settleTimer.start()
    }
  }
  Timer {
    id: settleTimer
    interval: 1200
    onTriggered: scene.grabToImage(function(result) {
      if (!result.saveToFile(root.outFile)) console.warn("could not save " + root.outFile)
      Qt.quit()
    })
  }
}
