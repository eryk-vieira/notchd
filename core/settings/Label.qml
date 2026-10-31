import QtQuick
import ".."

// Text in the settings window's type scale. `role` picks size and tone:
// "title" (page/window), "body" (row titles), "help" (descriptions),
// "section" (uppercase section headings).
Text {
  property string role: "body"

  textFormat: Text.PlainText
  wrapMode: Text.Wrap
  font.family: Theme.font.family
  font.pixelSize: role === "title" ? Theme.font.heading
    : (role === "body" ? Theme.font.body : Theme.font.bodySmall)
  font.letterSpacing: role === "section" ? 1 : 0
  font.capitalization: role === "section" ? Font.AllUppercase : Font.MixedCase
  color: role === "help" || role === "section" ? Theme.muted : Theme.foreground
}
