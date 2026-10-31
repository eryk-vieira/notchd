import QtQuick
import QtQuick.Layouts
import ".."

// Generic activities pushed from scripts over the notch IPC target, no QML
// needed (the host decides the target name and CLI; see its README):
//
//   <notch-ipc> push '{"id":"deploy","icon":"󰜎","title":"Deploying api",
//                    "subtitle":"staging","progress":40,"sticky":true}'
//   <notch-ipc> clear deploy      # or clear "" for all
//
// Fields: id (same id updates in place), icon (Nerd Font glyph), title,
// subtitle, progress (0-100, omit for none), sticky (stay in compact/expanded
// until cleared; otherwise it only peeks), peek (false to update silently),
// duration (peek ms, default 3000).
NotchModule {
  id: acts
  priority: 70

  property var items: []
  property var last: null
  active: items.length > 0

  function push(json) {
    var o
    try { o = JSON.parse(String(json || "")) } catch (e) { return "invalid json" }
    if (!o || typeof o !== "object") return "invalid json"
    var progress = o.progress === undefined || o.progress === null ? -1 : Number(o.progress)
    var item = {
      id: String(o.id || ("activity-" + Date.now())),
      icon: String(o.icon || "󰋼"),
      title: String(o.title || ""),
      subtitle: String(o.subtitle || ""),
      progress: isFinite(progress) && progress >= 0 ? Math.min(100, progress) : -1,
      sticky: o.sticky === true
    }
    var list = acts.items.filter(function(x) { return x.id !== item.id })
    if (item.sticky) list.push(item)
    acts.items = list
    acts.last = item
    if (o.peek !== false) acts.requestPeek(Number(o.duration) || 3000)
    return "ok"
  }

  function clear(id) {
    acts.items = id ? acts.items.filter(function(x) { return x.id !== id }) : []
    if (acts.last && (!id || acts.last.id === id)) acts.dismissPeek()
    return "ok"
  }

  compact: Component {
    ActivityRow {
      item: acts.items.length > 0 ? acts.items[acts.items.length - 1] : null
      implicitWidth: Theme.space(220)
      showSubtitle: false
      iconSize: Theme.font.body
    }
  }

  // Side edge: the icon, and the progress as a bar filling upwards.
  verticalCompact: Component {
    Column {
      id: verticalRow
      readonly property var item: acts.items.length > 0 ? acts.items[acts.items.length - 1] : null
      readonly property bool hasProgress: !!item && item.progress >= 0
      spacing: Theme.space(6)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: verticalRow.item ? verticalRow.item.icon : ""
        color: Theme.accent
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: verticalRow.hasProgress
        width: Theme.space(4)
        height: Theme.space(28)
        Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.line }
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: parent.height * (verticalRow.hasProgress ? verticalRow.item.progress / 100 : 0)
          radius: width / 2
          color: Theme.accent
          Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }
      }
    }
  }

  peek: Component {
    ActivityRow {
      item: acts.last
      implicitWidth: Math.min(Theme.space(340), Math.max(Theme.space(220), naturalWidth))
    }
  }

  expanded: Component {
    Column {
      spacing: Theme.space(8)
      Repeater {
        model: acts.items
        delegate: ActivityRow {
          required property var modelData
          item: modelData
          width: parent.width
        }
      }
    }
  }

  component ActivityRow: Item {
    id: row
    property var item: null
    property bool showSubtitle: true
    // The compact row uses body size, so the icon doesn't make it taller.
    property int iconSize: Theme.font.heading
    readonly property bool hasProgress: !!item && item.progress >= 0
    readonly property real naturalWidth: iconText.implicitWidth + Theme.space(12)
      + Math.max(titleText.implicitWidth, subtitleText.implicitWidth)
    implicitHeight: layout.implicitHeight

    ColumnLayout {
      id: layout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Theme.space(5)

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space(12)
        Text {
          id: iconText
          textFormat: Text.PlainText
          text: row.item ? row.item.icon : ""
          color: Theme.accent
          font.family: Theme.font.family
          font.pixelSize: row.iconSize
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0
          Text {
            id: titleText
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: row.item ? row.item.title : ""
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
          }
          Text {
            id: subtitleText
            Layout.fillWidth: true
            visible: row.showSubtitle && text !== ""
            textFormat: Text.PlainText
            text: row.item ? row.item.subtitle : ""
            elide: Text.ElideRight
            color: Theme.foreground
            opacity: 0.6
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
        }
        Text {
          visible: row.hasProgress
          textFormat: Text.PlainText
          text: row.hasProgress ? Math.round(row.item.progress) + "%" : ""
          color: Theme.foreground
          opacity: 0.6
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
      }

      Item {
        visible: row.hasProgress && row.showSubtitle
        Layout.fillWidth: true
        implicitHeight: Theme.space(4)
        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.15)
        }
        Rectangle {
          width: parent.width * (row.hasProgress ? row.item.progress / 100 : 0)
          height: parent.height
          radius: height / 2
          color: Theme.accent
          Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }
      }
    }
  }
}
