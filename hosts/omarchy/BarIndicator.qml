import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../../core/settings/Settings.js" as Settings

// The notchd button in the bar and its panel: every notch, where it is and
// what it shows, and the way into the settings window.
//   left click opens the panel, right click opens the settings
// Clicking a notch's row opens it on the focused monitor (or closes it, if
// open); its gear opens that notch's settings page.
Panel {
  id: root
  moduleName: "eryk.notchd"
  // The service owns the "eryk.notchd" IPC target.
  manageIpc: false

  // Injected by the shell, when it does.
  property var manifest: null

  property var svc: null
  Timer {
    interval: 200
    repeat: true
    triggeredOnStart: true
    running: !root.svc && !!root.bar && !!root.bar.shell
    onTriggered: root.svc = root.bar.shell.serviceFor("eryk.notchd")
  }

  readonly property var notches: root.svc ? root.svc.notches : []
  readonly property var titles: {
    var out = {}
    var catalog = root.svc ? root.svc.moduleCatalog : []
    for (var i = 0; i < catalog.length; i++) out[catalog[i].moduleId] = catalog[i].title
    return out
  }
  // Modules showing something now, across every notch.
  readonly property int activeCount: {
    var seen = {}
    for (var i = 0; i < root.notches.length; i++) {
      var active = root.notches[i].activeModules || []
      for (var j = 0; j < active.length; j++) seen[active[j].moduleId] = true
    }
    return Object.keys(seen).length
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function isOpen(notch) {
    var copies = notch ? notch.copies : []
    for (var i = 0; i < copies.length; i++)
      if (copies[i].pinned) return true
    return false
  }
  // `index`: a notch's page; none, the page the window last showed.
  function openSettings(index) {
    root.close()
    if (root.svc) root.svc.openSettings(index)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    iconComponent: Component { NotchdMark { size: Style.bar.iconFont; tint: button.foreground } }
    dimmed: !root.svc
    tooltipText: "notchd"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openSettings()
      else root.toggle()
    }
  }

  PopupCard {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "notchd"
          meta: !root.svc ? "Starting"
            : root.notches.length + (root.notches.length === 1 ? " notch" : " notches")
              + " · " + (root.activeCount === 0 ? "all quiet"
                         : root.activeCount + (root.activeCount === 1 ? " module active" : " modules active"))
          detail: root.manifest && root.manifest.version ? "v" + root.manifest.version : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component { NotchdMark { size: Style.font.display; tint: root.foreground } }
        }

        PanelSeparator { visible: root.notches.length > 0; foreground: root.foreground }

        Column {
          visible: root.notches.length > 0
          width: parent.width
          spacing: Style.space(4)
          PanelSectionHeader { text: "NOTCHES"; foreground: root.foreground; fontFamily: root.fontFamily }
          Repeater {
            model: root.notches
            delegate: NotchRow { required property var modelData; notch: modelData; width: parent.width }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Button {
          width: parent.width
          text: "Settings"
          iconText: String.fromCodePoint(0xF0493)  // nf-md-cog
          tooltipText: "Open the notchd settings (or right-click the icon)"
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          enabled: !!root.svc
          onClicked: root.openSettings()
        }
      }
    }
  }

  // notchd-symbolic.svg is the app icon as a white tile with the notch
  // knocked out; MultiEffect tints it to the theme color, the way the tray
  // tints symbolic icons.
  component NotchdMark: Item {
    id: mark
    property real size: Style.bar.iconFont
    property color tint: root.foreground
    // A Loader may stretch this item to its own size; the mark stays `size`
    // and centered either way.
    implicitWidth: size
    implicitHeight: size

    Image {
      id: markImage
      anchors.centerIn: parent
      width: mark.size
      height: mark.size
      source: Qt.resolvedUrl("../../assets/icons/hicolor/symbolic/apps/notchd-symbolic.svg")
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(mark.size * Screen.devicePixelRatio * 2)
      sourceSize.height: Math.round(mark.size * Screen.devicePixelRatio * 2)
      smooth: true
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: markImage
      source: markImage
      colorization: 1.0
      colorizationColor: mark.tint
    }
  }

  // A notch: its name, where it is and what it shows. Open ones are marked.
  component NotchRow: CursorSurface {
    id: row
    property var notch: null
    readonly property bool open: root.isOpen(row.notch)
    foreground: root.foreground
    current: row.open
    hasCursor: rowMouse.containsMouse
    implicitHeight: rowLayout.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (!row.notch) return
        root.close()
        row.notch.toggle()
      }
    }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(10)

      Column {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.notch ? row.notch.notchId : ""
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: !row.notch ? "" : Settings.notchSummary({ edge: row.notch.edge, moduleIds: row.notch.moduleIds }, root.titles)
          color: root.foreground
          opacity: 0.6
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        visible: row.open
        textFormat: Text.PlainText
        text: "open"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelActionButton {
        iconText: String.fromCodePoint(0xF0493)  // nf-md-cog
        tooltipText: "Settings of " + (row.notch ? row.notch.notchId : "this notch")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: if (row.notch) root.openSettings(row.notch.index)
      }
    }
  }
}
