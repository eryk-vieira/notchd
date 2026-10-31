import QtQuick

// Root type of a card picture (an option's `preview` in a "cards" choice).
// Draw inside it with Theme colors; `selected` is set while its card is,
// `value` to its option's value (one file can draw every option).
Item {
  property bool selected: false
  property var value
}
