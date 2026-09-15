import QtQuick
import Quickshell
import Quickshell.Io

// Host installed integration engines once, under the Hub's own service.
// No cross-plugin service lookup or access to the host shell object is needed.
Item {
  id: root
  required property var hubService
  property var config: ({})
  property string errorText: ""
  readonly property var settings: {
    var entries = (config.plugins || []).slice()
    var layout = config.bar && config.bar.layout ? config.bar.layout : ({})
    for (var region of ["left", "center", "right"]) entries = entries.concat(layout[region] || [])
    var result = ({})
    for (var entry of entries)
      if (entry && entry.id === "kevin.hub") result = Object.assign(result, entry.integrations || {})
    return result
  }
  readonly property var screenTime: screenLoader.item
  readonly property var phone: phoneLoader.item
  readonly property var nearby: nearbyLoader.item ? nearbyLoader.item.item : null
  property string screenSessionApp: ""
  property double screenSessionStartedAt: 0

  function syncScreenSession() {
    var next = root.screenTime ? String(root.screenTime.activeApp || "") : ""
    if (next === root.screenSessionApp) return
    root.screenSessionApp = next
    root.screenSessionStartedAt = next !== "" ? Date.now() : 0
  }

  onScreenTimeChanged: syncScreenSession()
  Connections {
    target: root.screenTime
    ignoreUnknownSignals: true
    function onActiveAppChanged() { root.syncScreenSession() }
  }

  function enabled(id) {
    // Re-enabling the standalone plugin relinquishes ownership immediately.
    return !!settings[id] && (config.disabledPlugins || []).indexOf(id) >= 0
  }

  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.config = JSON.parse(text()); root.errorText = "" }
      catch (error) { root.errorText = "Could not read integration settings." }
    }
    onLoadFailed: root.errorText = "Could not load integration settings."
  }

  // The Nearby engine only needs its own receiver preferences and panel routes.
  QtObject {
    id: nearbyHost
    readonly property var shellConfig: ({plugins: [Object.assign({id: "oma.nearby"}, root.settings["oma.nearby"] || {})]})
    function updateEntryInline(id, values) {
      if (id !== "oma.nearby" || !root.hubService.shell) return false
      var next = Object.assign({}, root.settings)
      next[id] = Object.assign({}, next[id] || {}, values)
      return root.hubService.shell.updateEntryInline("kevin.hub", {integrations: next})
    }
    function summon(id, payload) {
      root.hubService.currentTab = "nearby"
      return root.hubService.shell ? root.hubService.shell.summon("kevin.hub", payload) : false
    }
    function hide(id) { return root.hubService.shell ? root.hubService.shell.hide("kevin.hub") : false }
    function toggle(id, payload) {
      root.hubService.currentTab = "nearby"
      return root.hubService.shell ? root.hubService.shell.toggle("kevin.hub", payload) : false
    }
  }

  Loader {
    id: screenLoader
    active: root.enabled("agx.screen-time")
    source: Qt.resolvedUrl("../agx.screen-time/Service.qml")
  }
  Loader {
    id: phoneLoader
    active: root.enabled("omaconnect")
    source: Qt.resolvedUrl("../omaconnect/Service.qml")
  }
  Loader {
    id: nearbyLoader
    active: root.enabled("oma.nearby")
    sourceComponent: Component {
      Loader {
        Component.onCompleted: setSource(Qt.resolvedUrl("../oma.nearby/Service.qml"), {shell: nearbyHost})
      }
    }
  }
}
