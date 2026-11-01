import QtQuick
import "../core"

// A module you type into, for the keyboard tests: a text field in its
// expanded view, like the claude chat.
NotchModule {
  id: m
  title: "Typing"
  active: true
  expandedWidth: 520
  expanded: Component {
    TextInput {
      text: "type here"
    }
  }
}
