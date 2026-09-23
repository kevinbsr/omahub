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
      if (entry && entry.id === "kevinbsr.omahub") result = Object.assign(result, entry.integrations || {})
    return result
  }
  readonly property var screenTime: screenLoader.item
  readonly property var phone: phoneLoader.item
  readonly property var nearby: nearbyLoader.item ? nearbyLoader.item.item : null
  readonly property var mirror: mirrorLoader.item
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

  // Where an engine is loaded from. The Hub carries its own copy of each one
  // under vendor/, pinned to an upstream commit (see vendor/README.md), so a
  // fresh install has Screen Time, Phone and Android Mirror without the user
  // installing anything else. If the standalone plugin is also installed it
  // wins: it is the copy the user chose, it may be newer than the pin, and its
  // settings live where its own bar widget expects them.
  //
  // For that installed copy the service path comes from its manifest rather
  // than being assumed: agx.screen-time moved Service.qml to qml/Service.qml
  // in a refactor, and the hardcoded path this used to be went looking for a
  // file that no longer existed -- the integration loaded silently to nothing,
  // one QML warning, no error the panel could show.
  component ManifestServicePath: FileView {
    id: manifestFile
    required property string pluginId
    // Relative to this file: the vendored engine used when pluginId is not
    // installed. Empty for an engine the Hub does not carry (Nearby, whose
    // versioned helper binary belongs to its own plugin).
    property string vendoredPath: ""
    readonly property bool usingVendored: !installed
    property bool installed: false
    // Whether the standalone plugin is on disk at all, which is a different
    // question from `installed` (does it declare a service the Hub can host).
    // android-mirror answers yes/no to those two: present, but no service
    // entry point. A view that links to the standalone plugin's own panel --
    // for pairing or installing tools -- needs `present`, not `installed`,
    // or it offers a link to a panel that is not there.
    property bool present: false
    readonly property string enginePath: installed
      ? "../" + pluginId + "/" + servicePath
      : vendoredPath
    property string servicePath: ""
    path: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + pluginId + "/manifest.json"
    // An installed plugin is only used when it declares a service entry point.
    // io.github.ayan-de.android-mirror does not: upstream ships MirrorBackend
    // .qml as Panel.qml's private engine. The Hub used to add that entry to
    // the plugin's own manifest at enable time -- writing into someone else's
    // installed plugin, undone by their next update. The vendored copy carries
    // that one-line change as a patch instead (vendor/patches/android-mirror),
    // so nothing here edits a plugin it does not own.
    onLoaded: {
      var entry = ""
      try {
        var manifest = JSON.parse(text())
        entry = manifest.entryPoints && manifest.entryPoints.service ? String(manifest.entryPoints.service) : ""
      } catch (error) {
        entry = ""
      }
      servicePath = entry
      installed = entry !== ""
      present = true
    }
    onLoadFailed: { installed = false; present = false }
  }

  // The Phone tab's mirror section links to android-mirror's own panel for
  // pairing and settings; that link only makes sense when the plugin is there.
  readonly property bool mirrorPluginPresent: mirrorManifest.present

  ManifestServicePath { id: screenManifest; pluginId: "agx.screen-time"; vendoredPath: "vendor/screentime/qml/Service.qml" }
  ManifestServicePath { id: phoneManifest; pluginId: "omaconnect"; vendoredPath: "vendor/omaconnect/Service.qml" }
  ManifestServicePath { id: nearbyManifest; pluginId: "oma.nearby" }
  ManifestServicePath { id: mirrorManifest; pluginId: "io.github.ayan-de.android-mirror"; vendoredPath: "vendor/android-mirror/MirrorBackend.qml" }

  // Whether each engine is enabled and its Loader landed on Error rather than
  // Ready -- a bad source URL or a QML error in the file it names, which is
  // exactly how the screen-time breakage above showed up before the manifest
  // fix. Without this, the only trace was a console warning nobody watches
  // day to day, and the tab said "enable tracking" as if it never had been,
  // rather than "this is on and broken." The tabs read these to tell the two
  // apart; onXFailedChanged below turns the edge into one notification.
  readonly property bool screenTimeFailed: screenLoader.active && screenLoader.status === Loader.Error
  readonly property bool phoneFailed: phoneLoader.active && phoneLoader.status === Loader.Error
  readonly property var nearbyInnerLoader: nearbyLoader.item
  readonly property bool nearbyFailed: !!nearbyInnerLoader && nearbyInnerLoader.status === Loader.Error
  readonly property bool mirrorFailed: mirrorLoader.active && mirrorLoader.status === Loader.Error

  // One notification, not a stream: the synchronous-id hint below has the
  // notification daemon replace this plugin's previous copy instead of
  // stacking, matching the disk-space warning's pattern. Normal urgency and a
  // timeout, since this is informational -- the tab keeps saying so for as
  // long as it lasts, which is the persistent half of the signal.
  function reportIntegrationFailure(pluginId, label) {
    Quickshell.execDetached(["notify-send", "-u", "normal", "-t", "12000",
      "-i", "dialog-warning",
      "-h", "string:x-canonical-private-synchronous:omahub-integration-" + pluginId,
      "Hub integration broken",
      label + " is enabled but failed to load. Check the plugin, or disable and re-enable it in the Hub's settings."])
  }

  onScreenTimeFailedChanged: if (screenTimeFailed) reportIntegrationFailure("agx.screen-time", "Screen Time")
  onPhoneFailedChanged: if (phoneFailed) reportIntegrationFailure("omaconnect", "Phone")
  onNearbyFailedChanged: if (nearbyFailed) reportIntegrationFailure("oma.nearby", "Nearby")
  onMirrorFailedChanged: if (mirrorFailed) reportIntegrationFailure("io.github.ayan-de.android-mirror", "Android Mirror")

  // The Nearby engine only needs its own receiver preferences and panel routes.
  QtObject {
    id: nearbyHost
    readonly property var shellConfig: ({plugins: [Object.assign({id: "oma.nearby"}, root.settings["oma.nearby"] || {})]})
    function updateEntryInline(id, values) {
      if (id !== "oma.nearby" || !root.hubService.shell) return false
      var next = Object.assign({}, root.settings)
      next[id] = Object.assign({}, next[id] || {}, values)
      return root.hubService.shell.updateEntryInline("kevinbsr.omahub", {integrations: next})
    }
    function summon(id, payload) {
      root.hubService.currentTab = "nearby"
      return root.hubService.shell ? root.hubService.shell.summon("kevinbsr.omahub", payload) : false
    }
    function hide(id) { return root.hubService.shell ? root.hubService.shell.hide("kevinbsr.omahub") : false }
    function toggle(id, payload) {
      root.hubService.currentTab = "nearby"
      return root.hubService.shell ? root.hubService.shell.toggle("kevinbsr.omahub", payload) : false
    }
  }

  Loader {
    id: screenLoader
    active: root.enabled("agx.screen-time")
    source: Qt.resolvedUrl(screenManifest.enginePath)
  }
  Loader {
    id: phoneLoader
    active: root.enabled("omaconnect")
    source: Qt.resolvedUrl(phoneManifest.enginePath)
  }
  Loader {
    id: nearbyLoader
    active: root.enabled("oma.nearby")
    sourceComponent: Component {
      Loader {
        Component.onCompleted: setSource(Qt.resolvedUrl("../oma.nearby/" + nearbyManifest.servicePath), {shell: nearbyHost})
      }
    }
  }
  Loader {
    id: mirrorLoader
    active: root.enabled("io.github.ayan-de.android-mirror")
    source: Qt.resolvedUrl(mirrorManifest.enginePath)
    // MirrorBackend reads its own settings (adb/scrcpy paths, bitrate,
    // resolution) off a `settings` property the same way its standalone bar
    // widget feeds it -- but there is no bar widget in this path to do the
    // feeding, so it goes here. A live binding, not a one-time copy, so
    // changing a value in the standalone plugin's own settings panel (which
    // still writes the same shell.json entry) reaches the running mirror
    // without a shell restart.
    onLoaded: if (item) item.settings = Qt.binding(function() {
      return root.settings["io.github.ayan-de.android-mirror"] || {}
    })
  }
}
