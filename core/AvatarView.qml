import QtQuick
import Quickshell.Io
import "Avatar.js" as Avatar

// An agent's avatar: the photo NotchService.createAvatar made into files
// (core/avatar/make-avatar.py), drawn in ASCII by core/avatar/avatar.frag.
// The face turns to the pointer, a click sends a wave across it, it blinks
// on its own and `speaking` moves its mouth. Its rules (where the mouth and
// eyes are, the framing, the colors, the blinks, the speech) are
// core/Avatar.js's.
//
// One 60 fps Timer drives it, stopped while it isn't visible. Without
// shaders (Qt's software renderer: offscreen renders, a machine without a
// GPU) it shows the cut-out photo, still.
Item {
  id: view

  // The avatar's folder ("<id>.avatar"); "" draws nothing.
  property string dir: ""
  // Changes when its files do (NotchService.avatarVersions), so they are read again.
  property int version: 0
  // Its letters, on the outline: the agent's name.
  property string name: "AGENT"
  // "theme": lit by the accent and its complement; "photo": its own colors.
  property string colors: "theme"
  // "blocks" (dotted cells) or "ascii" (glyphs).
  property string style: "blocks"
  // How much of the height the face (forehead to chin) takes.
  property real fill: .62
  // A cell's width; its height is half again as much.
  property real cellWidth: Theme.space(7)
  // Turns to the pointer, a click sends a wave.
  property bool interactive: true
  // Talking: the mouth follows a speech rhythm (Avatar.speechPlan).
  property bool speaking: false
  // 0..1: busy (rows glitch, the lines run) and waiting for you (a pulse).
  property real work: 0
  property real attn: 0

  readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software
  readonly property var face: Avatar.faceFromLandmarks(view.faceData)
  readonly property var frame: Avatar.framing(view.face, view.fill)
  readonly property bool ready: view.dir !== "" && view.face !== null
    && colorImage.status === Image.Ready && depthImage.status === Image.Ready
  readonly property string fileBase: view.dir === "" ? "" : "file://" + view.dir + "/"
  property var faceData: null

  // ------------------------------------------------------------- the files
  FileView {
    path: view.dir === "" ? "" : view.dir + "/face.json"
    watchChanges: true
    onLoaded: view.readFace(text())
    onFileChanged: reload()
    onLoadFailed: view.faceData = null
  }
  function readFace(text) {
    try { view.faceData = JSON.parse(text) } catch (e) { view.faceData = null }
  }
  // `version` in the url makes a new texture when the files change.
  Image {
    id: colorImage
    visible: false
    source: view.fileBase === "" ? "" : view.fileBase + "color.png?v=" + view.version
    cache: false
    mipmap: true
  }
  Image {
    id: depthImage
    visible: false
    source: view.fileBase === "" ? "" : view.fileBase + "depth.png?v=" + view.version
    cache: false
    mipmap: true
  }

  // The glyphs the shader draws from: the name's letters, a density ramp,
  // arrows and marks, white, one 32 x 48 tile each.
  readonly property string letters: (view.name.toUpperCase().replace(/[^A-Z0-9]/g, "") || "AGENT").slice(0, 12)
  readonly property string ramp: " .:-=+*#%@"
  readonly property string marks: "←↑→↓?!"
  readonly property var glyphList: Array.from(view.letters + view.ramp + view.marks)
  Row {
    id: atlasRow
    visible: view.shaders
    Repeater {
      model: view.glyphList
      Text {
        required property string modelData
        width: 32
        height: 48
        text: modelData
        color: "white"
        font.family: Theme.font.family
        font.pixelSize: 38
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
  ShaderEffectSource {
    id: glyphAtlas
    sourceItem: atlasRow
    hideSource: true
    visible: false
  }

  // ------------------------------------------------------------ the motion
  property real time: 0
  property real lookX: 0
  property real lookY: 0
  property point pointer: Qt.point(-1, -1)
  property real blinkAt: 1.5
  property real blinkStart: -10
  property var plan: null
  property real mouthOpen: 0
  property real mouthWide: 1
  property real talk: 0
  property var ripples: []
  readonly property real startedAt: Date.now() / 1000

  function addRipple(x, y, strength) {
    var r = [Qt.vector4d(x, y, view.time, strength)].concat(view.ripples)
    view.ripples = r.slice(0, 4)
  }
  function rip(i) { return i < view.ripples.length ? view.ripples[i] : Qt.vector4d(0, 0, 0, 0) }

  Timer {
    interval: 16
    repeat: true
    running: view.visible && view.ready && view.shaders
    onTriggered: view.step()
  }
  function step() {
    var t = Date.now() / 1000 - view.startedAt
    view.time = t
    // Follow the pointer, else sway slowly.
    var hover = view.interactive && view.pointer.x >= 0
    var tx = hover ? (view.pointer.x / Math.max(1, view.width) - .5) * 1.1 : Math.sin(t * .35) * .28
    var ty = hover ? (view.pointer.y / Math.max(1, view.height) - .5) * .5 : Math.sin(t * .27) * .08
    view.lookX += (tx - view.lookX) * .06
    view.lookY += (ty - view.lookY) * .06
    if (t >= view.blinkAt) { view.blinkStart = t; view.blinkAt = t + Avatar.nextBlink(Math.random) }
    // Speech: a new phrase after each breath while speaking.
    var level = { open: 0, wide: 1 }
    if (view.speaking) {
      if (!view.plan || t >= view.plan.until) view.plan = Avatar.speechPlan(t, Math.random)
      level = Avatar.speechLevel(view.plan, t)
    } else if (view.plan && t >= view.plan.end) {
      view.plan = null
    } else if (view.plan) {
      level = Avatar.speechLevel(view.plan, t)
    }
    view.mouthOpen += (level.open - view.mouthOpen) * (level.open > view.mouthOpen ? .32 : .22)
    view.mouthWide += (level.wide - view.mouthWide) * .2
    view.talk += ((view.speaking ? 1 : 0) - view.talk) * .08
  }

  readonly property var paletteRgb: Avatar.palette([Theme.accent.r, Theme.accent.g, Theme.accent.b], view.colors)

  // ------------------------------------------------------------ the shader
  ShaderEffect {
    id: effect
    anchors.fill: parent
    visible: view.ready && view.shaders
    fragmentShader: Qt.resolvedUrl("avatar/avatar.frag.qsb")

    readonly property vector2d res: Qt.vector2d(effect.width, effect.height)
    readonly property vector2d cell: Qt.vector2d(view.cellWidth, Math.round(view.cellWidth * 1.55))
    readonly property real time: view.time
    readonly property vector2d look: Qt.vector2d(view.lookX, view.lookY)
    readonly property real lightYaw: view.lookX
    readonly property real work: view.work
    readonly property real attn: view.attn
    readonly property vector4d rip0: view.rip(0)
    readonly property vector4d rip1: view.rip(1)
    readonly property vector4d rip2: view.rip(2)
    readonly property vector4d rip3: view.rip(3)
    readonly property var atlas: glyphAtlas
    readonly property real glyphs: view.glyphList.length
    readonly property real nameLen: view.letters.length
    readonly property real rampOff: view.letters.length
    readonly property real arrowOff: view.letters.length + view.ramp.length
    readonly property real mode: view.style === "ascii" ? 1 : 0
    readonly property real zoom: view.frame.zoom
    readonly property vector2d focusUv: Qt.vector2d(view.frame.focus[0], view.frame.focus[1])
    readonly property var colorMap: colorImage
    readonly property var depthMap: depthImage
    readonly property vector2d tex: view.face ? Qt.vector2d(view.face.size[0], view.face.size[1]) : Qt.vector2d(1, 1)
    readonly property real photoColors: view.paletteRgb.photo
    readonly property vector2d mouthL: view.face ? Qt.vector2d(view.face.mouthL[0], view.face.mouthL[1]) : Qt.vector2d(0, 0)
    readonly property vector2d mouthR: view.face ? Qt.vector2d(view.face.mouthR[0], view.face.mouthR[1]) : Qt.vector2d(1, 0)
    readonly property real chin: view.face ? view.face.chin : 1
    readonly property real open: view.mouthOpen
    readonly property real openMax: view.face ? view.face.openMax : 0
    readonly property real wide: view.mouthWide
    readonly property real talk: view.talk
    readonly property vector4d eyeA: view.face ? Qt.vector4d(view.face.eyeA[0], view.face.eyeA[1], view.face.eyeA[2], view.face.eyeA[3]) : Qt.vector4d(0, 0, 1, 0)
    readonly property vector4d eyeB: view.face ? Qt.vector4d(view.face.eyeB[0], view.face.eyeB[1], view.face.eyeB[2], view.face.eyeB[3]) : Qt.vector4d(0, 0, 1, 0)
    readonly property vector4d lids: view.face ? Qt.vector4d(view.face.lidsA[0], view.face.lidsA[1], view.face.lidsB[0], view.face.lidsB[1]) : Qt.vector4d(1, 1, 1, 1)
    readonly property real blink: Avatar.blinkLevel(view.time - view.blinkStart)
    readonly property vector4d warm: Qt.vector4d(view.paletteRgb.warm[0], view.paletteRgb.warm[1], view.paletteRgb.warm[2], 1)
    readonly property vector4d cool: Qt.vector4d(view.paletteRgb.cool[0], view.paletteRgb.cool[1], view.paletteRgb.cool[2], 1)
    readonly property vector4d hot: Qt.vector4d(view.paletteRgb.hot[0], view.paletteRgb.hot[1], view.paletteRgb.hot[2], 1)
  }

  // Without shaders: the cut-out photo, framed the same way.
  Item {
    anchors.fill: parent
    visible: view.ready && !view.shaders
    clip: true
    Image {
      readonly property real h: view.height * view.frame.zoom
      width: view.face ? h * view.face.size[0] / view.face.size[1] : 0
      height: h
      x: view.width / 2 - view.frame.focus[0] * width
      y: view.height / 2 - view.frame.focus[1] * height
      source: view.ready && !view.shaders ? colorImage.source : ""
      mipmap: true
      opacity: .85
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: view.interactive
    hoverEnabled: true
    onPositionChanged: function(mouse) { view.pointer = Qt.point(mouse.x, mouse.y) }
    onExited: view.pointer = Qt.point(-1, -1)
    onClicked: function(mouse) { view.addRipple(mouse.x, mouse.y, 1) }
  }
}
