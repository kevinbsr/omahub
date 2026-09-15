import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

Controls.ScrollBar {
  id: root
  property color foreground: Color.foreground
  policy: Controls.ScrollBar.AsNeeded
  minimumSize: 0.08
  padding: Style.space(2)
  implicitWidth: horizontal ? Style.space(40) : Style.space(8)
  implicitHeight: horizontal ? Style.space(8) : Style.space(40)
  contentItem: Rectangle {
    radius: Math.min(Math.min(width, height) / 2, Style.cornerRadius)
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
      root.pressed ? 0.65 : (root.hovered ? 0.45 : 0.24))
  }
  background: Rectangle {
    radius: Math.min(Math.min(width, height) / 2, Style.cornerRadius)
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
  }
}
