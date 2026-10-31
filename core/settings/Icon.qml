import QtQuick
import ".."

// A Nerd Font glyph. `glyph` is a code point (0xF0493) or a string.
Text {
  property var glyph: ""
  property int size: Theme.font.heading

  textFormat: Text.PlainText
  text: typeof glyph === "number" ? String.fromCodePoint(glyph) : String(glyph || "")
  font.family: Theme.font.family
  font.pixelSize: size
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
}
