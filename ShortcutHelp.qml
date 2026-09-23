import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

Item {
  id: root
  property string pageId: ""
  property string pageLabel: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal dismissed()

  readonly property var commonRows: [
    ["1–7", "Jump to a page"],
    ["Tab / Shift+Tab", "Next / previous page or bar panel"],
    ["?", "Show or hide shortcuts"],
    ["Esc", "Go back, then close the Hub"]
  ]
  readonly property var pageRows: {
    switch (pageId) {
    case "calendar": return [
      ["← / → · ↑ / ↓", "Select previous/next day · previous/next week"],
      ["[ / ] · { / }", "Previous/next month · previous/next year"],
      ["T", "Select today"], ["C / Enter · I", "Copy dd/mm/yyyy · copy yyyy-mm-dd"],
      ["Double-click", "Life progress: edit · Year: initial setup"],
      ["W", "Change the first day of the week"]]
    case "media": return [
      ["P / Space", "Play or pause / activate selection"], ["B / N", "Previous / next track"],
      ["← / →", "Seek 5 seconds; skip if seeking is unavailable"],
      ["↑ / ↓ · Enter", "Browse audio sources, then select"],
      ["E", "Expand selected source streams"],
      ["M / O", "Mute / show the player window"],
      ["+ / −", "Raise / lower volume by 5%"],
      ["S / R / T", "Shuffle / repeat / remaining time"],
      ["Cover", "Click to open · scroll for volume · right-click to mute"]]
    case "weather": return [
      ["Enter", "Edit location"], ["R / U", "Refresh weather / switch °C and °F"],
      ["↑ / ↓", "Browse city suggestions while editing"],
      ["Enter / Esc", "Save / cancel location editing"]]
    case "screentime": return [
      ["← / →", "Select previous / next day"],
      ["T", "Select today"], ["H", "Show or hide retained history"],
      ["↑ / ↓", "Scroll activity history"],
      ["A", "Enable tracking when unavailable"]]
    case "phone": return [
      ["Arrows · Enter", "Browse and activate devices or actions"],
      ["R", "Refresh devices"], ["P / U", "Pair / request unpairing"],
      ["Y / C", "Confirm unpairing / cancel pending action"],
      ["A", "Enable phone integration when unavailable"]]
    case "nearby": return [
      ["↑ / ↓", "Browse receiver, devices and rescan"],
      ["Enter", "Activate the selected action"], ["Esc", "Back out of a transfer or PIN prompt"]]
    case "system": return [
      ["R", "Refresh system data"], ["B / Enter", "Open btop"],
      ["↑ / ↓", "Scroll system information"]]
    default: return []
    }
  }

  function scroll(delta) {
    list.contentY = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), list.contentY + delta))
  }
  onVisibleChanged: if (visible) list.contentY = 0

  Item {
    id: header
    width: parent.width
    height: heading.implicitHeight + Style.space(24)
    Text {
      textFormat: Text.PlainText
      id: heading
      anchors.left: parent.left
      anchors.right: closeHelp.left
      anchors.rightMargin: Style.space(12)
      text: root.pageLabel + " shortcuts"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    PanelActionButton {
      id: closeHelp
      anchors.right: parent.right
      size: Style.space(32)
      iconText: "×"
      tooltipText: "Back to " + root.pageLabel + " · Esc"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.dismissed()
    }
  }

  Flickable {
    id: list
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Controls.ScrollBar.vertical: HubScrollBar { foreground: root.foreground }

    Column {
      id: rows
      width: parent.width - Style.space(12)
      spacing: Style.space(12)
      Repeater {
        model: [
          {label: "THIS PAGE", entries: root.pageRows},
          {label: "EVERYWHERE", entries: root.commonRows}
        ]
        Column {
          required property var modelData
          width: rows.width
          spacing: Style.space(8)
          PanelSectionHeader {
            width: parent.width
            text: modelData.label
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Repeater {
            model: modelData.entries
            Item {
              required property var modelData
              width: rows.width
              height: Math.max(keycap.implicitHeight, description.implicitHeight) + Style.space(8)
              Text {
                textFormat: Text.PlainText
                id: keycap
                width: Style.space(132)
                text: modelData[0]
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
              }
              Text {
                textFormat: Text.PlainText
                id: description
                anchors.left: keycap.right
                anchors.leftMargin: Style.space(14)
                anchors.right: parent.right
                text: modelData[1]
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }
    }
  }
}
