import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Column {
  id: root
  required property string pluginId
  required property string actionText
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string statusText: ""
  property bool configuredEnabled: false
  property bool checked: false
  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("scripts/integration_service.py").toString()).replace(/^file:\/\//, "")
  spacing: Style.space(10)

  function activate() {
    if (enableProcess.running || configuredEnabled) return
    statusText = ""
    enableProcess.running = true
  }

  Button {
    visible: !root.configuredEnabled
    text: enableProcess.running ? "Enabling…" : root.actionText
    enabled: root.checked && !enableProcess.running
    foreground: root.foreground
    tooltipText: root.actionText + " · A"
    onClicked: root.activate()
  }

  Button {
    visible: root.configuredEnabled && root.pluginId === "omaconnect"
    text: "Open KDE Connect"
    foreground: root.foreground
    onClicked: Quickshell.execDetached(["kdeconnect-app"])
  }

  Text {
    width: parent.width
    visible: text !== ""
    text: root.configuredEnabled
      ? "Starting integration… If it stays unavailable, check that its plugin is installed."
      : root.statusText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Process {
    id: enableProcess
    command: ["python3", root.helperPath, "enable", root.pluginId]
    stderr: StdioCollector { id: errors; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) statusProcess.running = true
      else root.statusText = "Could not enable the integration. " + (errors.text.trim().slice(0, 240) || "Try again.")
    }
  }
  Process {
    id: statusProcess
    command: ["python3", root.helperPath, "status", root.pluginId]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.configuredEnabled = JSON.parse(text).enabled === true }
        catch (error) { root.statusText = "Could not check the integration status." }
        root.checked = true
      }
    }
  }
  Timer {
    interval: 5000
    repeat: true
    running: root.visible
    triggeredOnStart: true
    onTriggered: if (!statusProcess.running && !enableProcess.running) statusProcess.running = true
  }

}
