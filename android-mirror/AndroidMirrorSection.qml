import QtQuick
import qs.Commons
import qs.Ui
import ".." // IntegrationSetup lives in kevinbsr.omahub's own root, one level up
import "AndroidMirrorModel.js" as MirrorModel

// A compact device list + mirror button for the Phone tab, under omaconnect.
// The engine (MirrorBackend) is upstream's, loaded once by HubIntegrations.qml
// -- see ../HubIntegrations.qml and VENDORED.md for how and why. This is the
// Hub's own view onto it: the frequent action (mirror an already-known
// phone) inline, the rare ones (pairing, settings, installing the tools)
// behind a link to upstream's own panel, which already has them.
//
// That link is only offered when the standalone plugin is actually installed
// (`standalonePanel`). With the Hub running its vendored engine and no such
// plugin, there is no panel to open, so the one rare action that cannot wait
// -- installing adb/scrcpy, without which nothing here works at all -- gets
// a button of its own here, calling the same backend function the panel's
// Install button calls. Pairing by address stays out: it is a two-field form
// for a case a USB cable already solves, and the Wi-Fi button on a plugged-in
// phone covers the path most people take.
Column {
  id: root

  required property var hub
  property var backend: null
  property bool standalonePanel: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property var devices: backend ? backend.devices || [] : []
  readonly property bool toolsMissing: !!(backend && backend.toolsMissing)
  readonly property bool loading: !!(backend && backend.loading)
  readonly property bool hasResult: !!(backend && backend.lastSuccessAt > 0)

  function openFullPanel() {
    if (root.hub && root.hub.hubService && root.hub.hubService.shell)
      root.hub.hubService.shell.summon("io.github.ayan-de.android-mirror")
  }

  width: parent ? parent.width : 0
  spacing: Style.space(8)
  // Shown either way, header included: the "Enable mirroring" prompt below
  // is how this gets turned on in the first place, matching the omaconnect
  // block above it in the tab. Only hiding on !backend would bury the one
  // way to discover and enable this from here.

  Text {
    text: "ANDROID MIRROR"
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
    font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1
  }

  IntegrationSetup {
    visible: !root.backend
    width: parent.width
    pluginId: "io.github.ayan-de.android-mirror"; actionText: "Enable mirroring"
    foreground: root.foreground; fontFamily: root.fontFamily
  }

  Column {
    visible: root.toolsMissing
    width: parent.width
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      text: root.standalonePanel
        ? "adb or scrcpy is missing. Open the full panel to install them."
        : "adb or scrcpy is missing. Mirroring needs both."
      color: Color.urgent
      font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap
    }

    Button {
      visible: !root.standalonePanel
      text: "Install"
      iconText: "󰏔"
      bordered: true
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: if (root.backend) root.backend.installTools()
    }
  }

  Text {
    visible: !root.toolsMissing && root.devices.length === 0
    width: parent.width
    text: root.loading && !root.hasResult ? "Looking for phones…"
      : root.standalonePanel
        ? "Plug in a phone with USB debugging on, or pair over Wi-Fi in the full panel."
        : "Plug in a phone with USB debugging on; the Wi-Fi button then lets you unplug it."
    color: root.dim
    font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.toolsMissing ? [] : root.devices

    delegate: Item {
      id: row
      required property var modelData
      readonly property bool isMirroring: root.backend && root.backend.mirroring
        && root.backend.mirroring.serial === modelData.serial
      width: parent ? parent.width : 0
      height: rowText.implicitHeight + Style.spacing.sm

      Column {
        id: rowText
        anchors.left: parent.left
        anchors.right: rowActions.left
        anchors.rightMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        Text {
          width: parent.width
          text: MirrorModel.deviceTitle(row.modelData)
          color: row.modelData.ready ? root.foreground : root.dim
          elide: Text.ElideRight
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.weight: Font.Medium
        }
        Text {
          width: parent.width
          text: MirrorModel.deviceSubtitle(row.modelData)
          color: row.modelData.ready ? root.dim : Color.urgent
          elide: Text.ElideRight
          font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: rowActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        PanelActionButton {
          visible: row.modelData.ready && row.modelData.transport === "usb"
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰖩"
          tooltipText: "Enable Wi-Fi mirroring for this phone, then unplug"
          enabled: root.backend && !root.backend.actionBusy
          onClicked: root.backend.enableWifi(row.modelData.serial)
        }
        PanelActionButton {
          visible: row.modelData.transport === "wifi"
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰅖"
          tooltipText: "Disconnect"
          enabled: root.backend && !root.backend.actionBusy
          onClicked: root.backend.disconnect(row.modelData.serial)
        }
        Button {
          visible: row.modelData.ready
          text: row.isMirroring ? "Stop" : "Mirror"
          iconText: row.isMirroring ? "󰓛" : "󰐊"
          bordered: true
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: row.isMirroring ? root.backend.stopMirror() : root.backend.mirror(row.modelData)
        }
      }
    }
  }

  Text {
    visible: !!root.backend && root.standalonePanel
    text: "Pair a new phone, or change settings, in the full panel ›"
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
    font.family: root.fontFamily; font.pixelSize: Style.font.caption
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openFullPanel()
    }
  }
}
