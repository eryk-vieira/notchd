import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Widgets
import ".."

// Now playing, from MPRIS (Spotify, browsers, mpv...). Compact: artwork,
// title and artist, equalizer. Peeks on a new track. Expanded: artwork,
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
  // Artwork, "title · artist" and the equalizer. The text gets up to
  // `maxText`; the title keeps its room first and the artist takes what is
  // left, dropping out when that is too little to read.
  compact: Component {
    Item {
      id: compactRow
      readonly property real gap: Theme.space(10)
      readonly property real maxText: Theme.space(240)
      readonly property real textWidth: Math.max(0, width - compactArt.width - compactEq.width - gap * 2)
      readonly property real titleWidth: Math.min(compactTitle.implicitWidth, textWidth)
      readonly property real artistWidth: Math.min(compactArtist.implicitWidth, textWidth - titleWidth)
      readonly property bool artistFits: media.trackArtist !== "" && artistWidth >= Theme.space(40)

      implicitWidth: Math.max(Theme.space(220), compactArt.width + compactEq.width + gap * 2
        + Math.min(maxText, compactTitle.implicitWidth + (media.trackArtist !== "" ? compactArtist.implicitWidth : 0)))
      implicitHeight: Theme.space(18)

      Art { id: compactArt; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; size: Theme.space(16); radius: Theme.space(4) }
      Text {
        id: compactTitle
        anchors.left: compactArt.right
        anchors.leftMargin: compactRow.gap
        anchors.verticalCenter: parent.verticalCenter
        width: compactRow.titleWidth
        textFormat: Text.PlainText
        text: media.trackTitle
        elide: Text.ElideRight
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
      Text {
        id: compactArtist
        anchors.left: compactTitle.right
        anchors.verticalCenter: parent.verticalCenter
        width: compactRow.artistWidth
        visible: compactRow.artistFits
        textFormat: Text.PlainText
        text: " · " + media.trackArtist
        elide: Text.ElideRight
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
      Equalizer { id: compactEq; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; barHeight: Theme.space(12) }
    }
  }

  // Side edge: artwork above the equalizer.
  verticalCompact: Component {
    Column {
      spacing: Theme.space(8)
      Art { anchors.horizontalCenter: parent.horizontalCenter; size: Theme.space(16); radius: Theme.space(4) }
      Equalizer { anchors.horizontalCenter: parent.horizontalCenter; barHeight: Theme.space(12) }
    }
  }

  barView: Component {
    Row {
      spacing: Theme.space(6)
      Art { anchors.verticalCenter: parent.verticalCenter; size: Theme.space(16); radius: Theme.space(4) }
      Equalizer { anchors.verticalCenter: parent.verticalCenter; barHeight: Theme.space(12) }
    }
  }

  peek: Component {
    RowLayout {
      spacing: Theme.space(12)
      Art { size: Theme.space(38); radius: Theme.space(8) }
      ColumnLayout {
        spacing: 0
        Layout.preferredWidth: Math.min(Theme.space(240), Math.max(titleText.implicitWidth, artistText.implicitWidth))
        Text {
          id: titleText
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: media.trackTitle
          elide: Text.ElideRight
          color: Theme.foreground
          font.family: Theme.font.family
          font.pixelSize: Theme.font.body
          font.bold: true
        }
        Text {
          id: artistText
          Layout.fillWidth: true
          visible: text !== ""
          textFormat: Text.PlainText
          text: media.trackArtist
          elide: Text.ElideRight
          color: Theme.foreground
          opacity: 0.6
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
      }
      Equalizer { barHeight: Theme.space(16) }
    }
  }

  expanded: Component {
    ColumnLayout {
      spacing: Theme.space(10)

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space(14)
        Art { size: Theme.space(58); radius: Theme.space(10) }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Theme.space(2)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: media.trackTitle
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            visible: text !== ""
            textFormat: Text.PlainText
            text: media.trackArtist
            elide: Text.ElideRight
            color: Theme.foreground
            opacity: 0.7
            font.family: Theme.font.family
            font.pixelSize: Theme.font.bodySmall
          }
          Text {
            Layout.fillWidth: true
            visible: text !== ""
            textFormat: Text.PlainText
            text: media.source
            elide: Text.ElideRight
            color: Theme.foreground
            opacity: 0.45
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
        }
        Equalizer { Layout.alignment: Qt.AlignTop; barHeight: Theme.space(16) }
      }

      ColumnLayout {
        Layout.fillWidth: true
        visible: media.length > 0
        spacing: Theme.space(4)
        Item {
          Layout.fillWidth: true
          implicitHeight: Theme.space(4)
          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.15)
          }
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, media.position / Math.max(1, media.length)))
            height: parent.height
            radius: height / 2
            color: Theme.foreground
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
        spacing: Theme.space(26)
        IconButton { glyph: "󰒮"; enabled: !!media.player && media.player.canGoPrevious; onActivated: media.previous() }
        IconButton { glyph: media.playing ? "󰏤" : "󰐊"; big: true; onActivated: media.togglePlay() }
        IconButton { glyph: "󰒭"; enabled: !!media.player && media.player.canGoNext; onActivated: media.next() }
      }
    }
  }

  // ------------------------------------------------------------ components
  // Artwork with rounded corners. ClippingRectangle rounds it with a shader;
  // the software renderer (QT_QUICK_BACKEND=software, offscreen renders) has
  // none and would draw nothing at all, so there it gets a square crop.
  component Art: Item {
    id: art
    property real size: Theme.space(20)
    property real radius: Theme.space(5)
    readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software
    implicitWidth: size
    implicitHeight: size
    Layout.preferredWidth: size
    Layout.preferredHeight: size

    Loader {
      anchors.fill: parent
      sourceComponent: art.shaders ? rounded : square
    }
    Component {
      id: rounded
      ClippingRectangle { radius: art.radius; color: Theme.selected; ArtContent { size: art.size } }
    }
    Component {
      id: square
      Rectangle { radius: art.radius; color: Theme.selected; clip: true; ArtContent { size: art.size } }
    }
  }

  component ArtContent: Item {
    id: content
    property real size: Theme.space(20)
    anchors.fill: parent
    Image {
      id: artImage
      anchors.fill: parent
      source: media.artUrl
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: content.size * 2
      sourceSize.height: content.size * 2
      asynchronous: true
      visible: status === Image.Ready
    }
    Text {
      anchors.centerIn: parent
      visible: artImage.status !== Image.Ready
      textFormat: Text.PlainText
      text: "󰝚"
      color: Theme.foreground
      opacity: 0.7
      font.family: Theme.font.family
      font.pixelSize: content.size * 0.55
    }
  }

  // A fake equalizer: bars wander while playing and rest low when paused.
  // Fixed-size box so the bars moving never resize the notch.
  component Equalizer: Item {
    id: eq
    property real barHeight: Theme.space(14)
    implicitWidth: eqRow.implicitWidth
    implicitHeight: barHeight
    Row {
      id: eqRow
      anchors.bottom: parent.bottom
      spacing: Theme.space(2)
    Repeater {
      model: 4
      delegate: Rectangle {
        id: eqBar
        required property int index
        property real level: 0.25
        anchors.bottom: parent.bottom
        width: Theme.space(3)
        radius: width / 2
        height: Math.max(width, eq.barHeight * (media.playing ? level : 0.2))
        color: Theme.accent
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
    implicitWidth: Theme.space(big ? 36 : 28)
    implicitHeight: implicitWidth
    opacity: enabled ? 1 : 0.35
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Theme.foreground
      opacity: btnMouse.containsMouse ? 0.12 : 0
      Behavior on opacity { NumberAnimation { duration: 100 } }
    }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: btn.glyph
      color: Theme.foreground
      font.family: Theme.font.family
      font.pixelSize: btn.big ? Theme.font.display * 0.75 : Theme.font.heading
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
    color: Theme.foreground
    opacity: 0.5
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
  }
}
