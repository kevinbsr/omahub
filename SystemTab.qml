import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root
  property var hub: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool shown: false
  property bool loaded: false
  property var stats: ({})
  property string errorText: ""
  property int samples: 0
  readonly property var cpu: stats.cpu || ({})
  readonly property var ram: stats.ram || ({})
  readonly property var swap: stats.swap || ({})
  readonly property var igpu: stats.igpu || ({})
  readonly property var dgpu: stats.dgpu || ({})
  readonly property var disks: Array.isArray(stats.disks) ? stats.disks : []
  readonly property string probePath: decodeURIComponent(Qt.resolvedUrl("scripts/sysmon_probe").toString()).replace(/^file:\/\//, "")
  implicitHeight: content.implicitHeight

  function tabShown() { shown = true; probe() }
  function tabHidden() { shown = false }
  function panelClosed() { shown = false }
  function refresh() { if (shown) probe() }
  function probe() {
    if (!shown || probeProcess.running) return
    probeProcess.launched = false
    probeProcess.running = true
  }
  function openBtop() {
    Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
    if (hub) hub.close()
  }
  function handleActivate() { openBtop(); return true }
  function handleTextKey(text) {
    if (text.toLowerCase() === "r") { probe(); return true }
    if (text.toLowerCase() === "b") { openBtop(); return true }
    return false
  }
  function percent(value) { return Math.max(0, Math.min(100, Number(value) || 0)) }
  function memory(kb) {
    var value = Math.max(0, Number(kb) || 0)
    return value >= 1048576 ? (value / 1048576).toFixed(1) + " GiB" : Math.round(value / 1024) + " MiB"
  }
  function storage(bytes) {
    var value = Math.max(0, Number(bytes) || 0)
    return value >= 1099511627776 ? (value / 1099511627776).toFixed(1) + " TiB" : (value / 1073741824).toFixed(1) + " GiB"
  }
  function gpuDetails(gpu) {
    return (gpu.temp || 0) + "°C · " + (gpu.watts || 0) + " W\n"
      + memory((gpu.vramUsedMi || 0) * 1024) + " / " + memory((gpu.vramTotalMi || 0) * 1024)
      + " · " + (gpu.mhz || 0) + " MHz"
  }

  Process {
    id: probeProcess
    property bool launched: false
    command: ["timeout", "8", "bash", root.probePath]
    stdout: StdioCollector { id: output; waitForEnd: true }
    onStarted: launched = true
    onRunningChanged: if (!running && !launched) root.errorText = "Could not start the system monitor."
    onExited: function(code) {
      if (code !== 0) {
        root.errorText = code === 124 ? "System reading timed out. Press R to retry." : "Could not read system data. Check omarchy-sysmon-probe."
        return
      }
      try {
        var data = JSON.parse(output.text)
        if (!data || !data.cpu || !data.ram || !Array.isArray(data.disks)) throw new Error("Invalid snapshot")
        root.stats = data
        root.loaded = true
        root.samples++
        root.errorText = ""
      } catch (error) { root.errorText = "Could not read system data. Press R to retry." }
    }
  }
  Timer { interval: 2000; repeat: true; running: root.shown; onTriggered: root.probe() }

  component Metric: Rectangle {
    id: metric
    property string label: ""
    property string value: ""
    property string detail: ""
    property real fraction: -1
    property bool multiline: false
    readonly property real inset: Style.space(16)
    height: Style.space(multiline ? 104 : 92)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
    Column {
      x: metric.inset
      y: metric.inset
      width: parent.width - metric.inset * 2
      spacing: Style.space(4)
      Text {
        width: parent.width; text: metric.label; elide: Text.ElideRight
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.65)
        font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width; text: metric.value; elide: Text.ElideRight
        color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title
      }
      Text {
        width: parent.width; text: metric.detail; elide: Text.ElideRight
        maximumLineCount: metric.multiline ? 2 : 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.65)
        font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
    }
    Rectangle {
      visible: root.loaded && metric.fraction >= 0
      x: metric.inset; width: parent.width - metric.inset * 2
      anchors.bottom: parent.bottom; anchors.bottomMargin: metric.inset
      height: Style.space(2); radius: Math.min(height / 2, Style.cornerRadius)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, metric.fraction))
        height: parent.height; radius: parent.radius
        color: metric.fraction >= 0.9 ? Color.urgent : Color.accent
      }
    }
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(8)
    Item {
      width: parent.width; height: Style.space(36)
      Text {
        text: "System monitor"; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.weight: Font.DemiBold
      }
      Row {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(8)
        Button {
          height: Style.space(32)
          iconText: "󰑐"; tooltipText: "Refresh · R"; enabled: !probeProcess.running
          foreground: root.foreground; fontFamily: root.fontFamily; iconSize: Style.font.body
          onClicked: root.probe()
        }
        Button {
          height: Style.space(32)
          text: "Open btop"; tooltipText: "Detailed system monitor · B or Enter"
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: root.openBtop()
        }
      }
    }
    Text {
      visible: root.errorText !== ""; width: parent.width
      text: root.errorText + (root.loaded ? " Showing the last reading." : "")
      wrapMode: Text.Wrap; color: Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
    }
    Metric {
      width: parent.width; label: "CPU"
      value: root.loaded ? root.percent(root.cpu.percent) + "%" : "—"
      detail: root.loaded ? (root.cpu.temp ? root.cpu.temp + "°C · " : "") + (root.cpu.cores || 0) + " threads" : "Reading system…"
      fraction: root.percent(root.cpu.percent) / 100
    }
    Row {
      width: parent.width; spacing: Style.space(8)
      Metric {
        width: (parent.width - parent.spacing) / 2; label: "RAM"
        value: root.loaded ? root.percent(root.ram.percent) + "%" : "—"
        detail: root.loaded ? root.memory(root.ram.usedKb) + " / " + root.memory(root.ram.totalKb) : ""
        fraction: root.percent(root.ram.percent) / 100
      }
      Metric {
        width: (parent.width - parent.spacing) / 2; label: "Swap"
        value: !root.loaded ? "—" : root.swap.totalKb > 0 ? root.percent(root.swap.percent) + "%" : "Disabled"
        detail: root.loaded && root.swap.totalKb > 0 ? root.memory(root.swap.usedKb) + " / " + root.memory(root.swap.totalKb) : ""
        fraction: root.swap.totalKb > 0 ? root.percent(root.swap.percent) / 100 : -1
      }
    }
    Row {
      width: parent.width; spacing: Style.space(8)
      visible: root.igpu.present || root.dgpu.present || false
      readonly property int count: (root.igpu.present ? 1 : 0) + (root.dgpu.present ? 1 : 0)
      Metric {
        visible: root.igpu.present || false; width: (parent.width - parent.spacing * (parent.count - 1)) / Math.max(1, parent.count)
        label: "iGPU · AMD"; value: root.percent(root.igpu.busy) + "%"
        detail: root.gpuDetails(root.igpu); multiline: true; fraction: root.percent(root.igpu.busy) / 100
      }
      Metric {
        visible: root.dgpu.present || false; width: (parent.width - parent.spacing * (parent.count - 1)) / Math.max(1, parent.count)
        label: "dGPU · NVIDIA"
        value: root.dgpu.detailed ? root.percent(root.dgpu.busy) + "%" : root.dgpu.status === "suspended" ? "Asleep" : root.dgpu.status === "active" ? "Active" : "Unavailable"
        detail: root.dgpu.detailed ? root.gpuDetails(root.dgpu) : root.dgpu.powerState || ""
        multiline: true; fraction: root.dgpu.detailed ? root.percent(root.dgpu.busy) / 100 : -1
      }
    }
    PanelSectionHeader { visible: root.disks.length > 0; text: "STORAGE"; foreground: root.foreground; fontFamily: root.fontFamily }
    Grid {
      width: parent.width; columns: root.disks.length === 1 ? 1 : 2; spacing: Style.space(8)
      Repeater {
        model: root.disks
        Metric {
          required property var modelData
          width: (parent.width - parent.spacing * (parent.columns - 1)) / parent.columns
          label: modelData.label + " · " + modelData.mount
          value: root.percent(modelData.percent) + "%"
          detail: root.storage(modelData.used) + " / " + root.storage(modelData.total)
          fraction: root.percent(modelData.percent) / 100
        }
      }
    }
  }
}
