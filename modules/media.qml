import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.Commons

// Now playing, from MPRIS (Spotify, browsers, mpv...). Compact: artwork on
// the left, equalizer on the right. Peeks on a new track. Expanded: artwork,
// title, progress and transport controls.
NotchModule {
  id: media
  title: "Now playing"
  priority: 50

  // Prefer whatever is playing; otherwise the first player with a track.
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    var list = media.players || []
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p || (!p.trackTitle && !p.trackArtist)) continue
      if (p.isPlaying) return p
      if (!fallback) fallback = p
    }
    return fallback
  }
  readonly property bool playing: !!player && player.isPlaying === true
  readonly property string trackTitle: player ? String(player.trackTitle || "") : ""
  readonly property string trackArtist: player ? String(player.trackArtist || "") : ""
  readonly property string artUrl: player ? String(player.trackArtUrl || "") : ""
  readonly property string source: player ? String(player.identity || "") : ""
  // Live streams report garbage (Chrome sends INT64_MAX); anything over a
  // day is treated as "no known length" and hides the progress bar.
  readonly property real length: {
    var v = player ? Number(player.length) : 0
    return isFinite(v) && v > 0 && v < 86400 ? v : 0
  }
  property real position: 0
  readonly property string trackKey: trackTitle + "\u0001" + trackArtist

  // Stay in the notch for a minute after pausing, so a short pause doesn't
  // make it jump back to rest.
  property bool recentlyPlaying: false
  active: !!player && trackTitle !== "" && (playing || recentlyPlaying)
  onPlayingChanged: {
    if (playing) { recentlyPlaying = true; pauseGrace.stop() }
    else pauseGrace.restart()
  }
  Timer { id: pauseGrace; interval: 60000; onTriggered: media.recentlyPlaying = false }

  // A short delay lets the artwork URL arrive with the new title.
  onTrackKeyChanged: if (media.playing && media.trackTitle !== "") peekDelay.restart()
  Timer { id: peekDelay; interval: 300; onTriggered: media.requestPeek(3500) }

  Timer {
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: !!media.player && !!media.notch && media.notch.mode === "expanded"
    onTriggered: {
      media.player.positionChanged()
      var v = Number(media.player.position)
      media.position = isFinite(v) && v > 0 ? v : 0
    }
  }

  function togglePlay() { if (player && (player.canTogglePlaying || player.canPlay || player.canPause)) player.togglePlaying() }
  function next() { if (player && player.canGoNext) player.next() }
  function previous() { if (player && player.canGoPrevious) player.previous() }

  function clock(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var m = Math.floor(s / 60)
    var h = Math.floor(m / 60)
    var ss = String(s % 60).padStart(2, "0")
    return h > 0 ? h + ":" + String(m % 60).padStart(2, "0") + ":" + ss : m + ":" + ss
  }

  // ----------------------------------------------------------------- views
  compact: Component {
    Item {
      implicitWidth: Style.space(220)
      implicitHeight: Style.space(22)
      Art { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; size: Style.space(20); radius: Style.space(5) }
      Equalizer { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; barHeight: Style.space(14) }
    }
  }

  barView: Component {
    Row {
      spacing: Style.space(6)
      Art { anchors.verticalCenter: parent.verticalCenter; size: Style.space(16); radius: Style.space(4) }
      Equalizer { anchors.verticalCenter: parent.verticalCenter; barHeight: Style.space(12) }
    }
  }

  peek: Component {
    RowLayout {
      spacing: Style.space(12)
      Art { size: Style.space(38); radius: Style.space(8) }
      ColumnLayout {
        spacing: 0
        Layout.preferredWidth: Math.min(Style.space(240), Math.max(titleText.implicitWidth, artistText.implicitWidth))
        Text {
          id: titleText
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: media.trackTitle
          elide: Text.ElideRight
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          id: artistText
          Layout.fillWidth: true
          visible: text !== ""
          textFormat: Text.PlainText
          text: media.trackArtist
          elide: Text.ElideRight
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
      Equalizer { barHeight: Style.space(16) }
    }
  }

  expanded: Component {
    ColumnLayout {
      spacing: Style.space(10)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(14)
        Art { size: Style.space(58); radius: Style.space(10) }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: media.trackTitle
            elide: Text.ElideRight
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            visible: text !== ""
            textFormat: Text.PlainText
            text: media.trackArtist
            elide: Text.ElideRight
            color: Color.foreground
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            Layout.fillWidth: true
            visible: text !== ""
            textFormat: Text.PlainText
            text: media.source
            elide: Text.ElideRight
            color: Color.foreground
            opacity: 0.45
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Equalizer { Layout.alignment: Qt.AlignTop; barHeight: Style.space(16) }
      }

      ColumnLayout {
        Layout.fillWidth: true
        visible: media.length > 0
        spacing: Style.space(4)
        Item {
          Layout.fillWidth: true
          implicitHeight: Style.space(4)
          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
          }
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, media.position / Math.max(1, media.length)))
            height: parent.height
            radius: height / 2
            color: Color.foreground
            Behavior on width { NumberAnimation { duration: 900 } }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          TimeText { text: media.clock(media.position) }
          Item { Layout.fillWidth: true }
          TimeText { text: "-" + media.clock(media.length - media.position) }
        }
      }

      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.space(26)
        IconButton { glyph: "󰒮"; enabled: !!media.player && media.player.canGoPrevious; onActivated: media.previous() }
        IconButton { glyph: media.playing ? "󰏤" : "󰐊"; big: true; onActivated: media.togglePlay() }
        IconButton { glyph: "󰒭"; enabled: !!media.player && media.player.canGoNext; onActivated: media.next() }
      }
    }
  }

  // ------------------------------------------------------------ components
  component Art: ClippingRectangle {
    id: art
    property real size: Style.space(20)
    implicitWidth: size
    implicitHeight: size
    Layout.preferredWidth: size
    Layout.preferredHeight: size
    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
    Image {
      id: artImage
      anchors.fill: parent
      source: media.artUrl
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: art.size * 2
      sourceSize.height: art.size * 2
      asynchronous: true
      visible: status === Image.Ready
    }
    Text {
      anchors.centerIn: parent
      visible: artImage.status !== Image.Ready
      textFormat: Text.PlainText
      text: "󰝚"
      color: Color.foreground
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: art.size * 0.55
    }
  }

  // A fake equalizer: bars wander while playing and rest low when paused.
  // Fixed-size box so the bars moving never resize the notch.
  component Equalizer: Item {
    id: eq
    property real barHeight: Style.space(14)
    implicitWidth: eqRow.implicitWidth
    implicitHeight: barHeight
    Row {
      id: eqRow
      anchors.bottom: parent.bottom
      spacing: Style.space(2)
    Repeater {
      model: 4
      delegate: Rectangle {
        id: eqBar
        required property int index
        property real level: 0.25
        anchors.bottom: parent.bottom
        width: Style.space(3)
        radius: width / 2
        height: Math.max(width, eq.barHeight * (media.playing ? level : 0.2))
        color: Color.accent
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Timer {
          interval: 170 + eqBar.index * 37
          repeat: true
          running: media.playing
          onTriggered: eqBar.level = 0.25 + Math.random() * 0.75
        }
      }
    }
    }
  }

  component IconButton: Item {
    id: btn
    property string glyph: ""
    property bool big: false
    signal activated()
    implicitWidth: Style.space(big ? 36 : 28)
    implicitHeight: implicitWidth
    opacity: enabled ? 1 : 0.35
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Color.foreground
      opacity: btnMouse.containsMouse ? 0.12 : 0
      Behavior on opacity { NumberAnimation { duration: 100 } }
    }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: btn.glyph
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: btn.big ? Style.font.display * 0.75 : Style.font.heading
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.activated()
    }
  }

  component TimeText: Text {
    textFormat: Text.PlainText
    color: Color.foreground
    opacity: 0.5
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
