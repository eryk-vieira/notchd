import QtQuick
import QtQuick.Layouts
import qs.Commons

// Generic activities pushed from scripts, no QML needed:
//
//   omarchy-shell eryk.notch push '{"id":"deploy","icon":"󰜎","title":"Deploying api",
//                                   "subtitle":"staging","progress":40,"sticky":true}'
//   omarchy-shell eryk.notch clear deploy      # or clear "" for all
//
// Fields: id (same id updates in place), icon (Nerd Font glyph), title,
// subtitle, progress (0-100, omit for none), sticky (stay in compact/expanded
// until cleared; otherwise it only peeks), peek (false to update silently),
// duration (peek ms, default 3000).
NotchModule {
  id: acts
  title: "Activities"
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
      implicitWidth: Style.space(220)
      showSubtitle: false
    }
  }

  barView: Component {
    Row {
      readonly property var item: acts.items.length > 0 ? acts.items[acts.items.length - 1] : null
      spacing: Style.space(6)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: parent.item ? parent.item.icon : ""
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Style.space(140))
        textFormat: Text.PlainText
        text: parent.item ? parent.item.title : ""
        elide: Text.ElideRight
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !!parent.item && parent.item.progress >= 0
        textFormat: Text.PlainText
        text: parent.item && parent.item.progress >= 0 ? Math.round(parent.item.progress) + "%" : ""
        color: Color.foreground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  peek: Component {
    ActivityRow {
      item: acts.last
      implicitWidth: Math.min(Style.space(340), Math.max(Style.space(220), naturalWidth))
    }
  }

  expanded: Component {
    Column {
      spacing: Style.space(8)
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
    readonly property bool hasProgress: !!item && item.progress >= 0
    readonly property real naturalWidth: iconText.implicitWidth + Style.space(12)
      + Math.max(titleText.implicitWidth, subtitleText.implicitWidth)
    implicitHeight: layout.implicitHeight

    ColumnLayout {
      id: layout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(5)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(12)
        Text {
          id: iconText
          textFormat: Text.PlainText
          text: row.item ? row.item.icon : ""
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
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
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Text {
            id: subtitleText
            Layout.fillWidth: true
            visible: row.showSubtitle && text !== ""
            textFormat: Text.PlainText
            text: row.item ? row.item.subtitle : ""
            elide: Text.ElideRight
            color: Color.foreground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          visible: row.hasProgress
          textFormat: Text.PlainText
          text: row.hasProgress ? Math.round(row.item.progress) + "%" : ""
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Item {
        visible: row.hasProgress && row.showSubtitle
        Layout.fillWidth: true
        implicitHeight: Style.space(4)
        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
        }
        Rectangle {
          width: parent.width * (row.hasProgress ? row.item.progress / 100 : 0)
          height: parent.height
          radius: height / 2
          color: Color.accent
          Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }
      }
    }
  }
}
