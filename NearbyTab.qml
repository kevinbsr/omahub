import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "NearbyModel.js" as Model

// Nearby page of the hub: LocalSend-compatible discovery, sending files and
// clipboard, and accepting what arrives.
//
// `oma.nearby` stays installed and HubIntegrations.qml loads its service once.
// That service is the whole
// engine — it owns the Rust helper, the transfer state and the `oma.nearby`
// IPC target — and upstream's Panel.qml was already only a view onto it,
// one per monitor. This page is that view, ported at the installed revision
// (see NearbyModel.js for which, and why it is pinned there).
//
// The three Processes stay here rather than in the engine for upstream's own
// reason: a file chooser and a clipboard belong to the screen the user acted
// on, and hand their result to the engine.
Item {
  id: root

  // ---- Tab contract, injected by Panel.qml.
  property var hub: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.7)

  readonly property var engine: hub && hub.hubService && hub.hubService.integrations
    ? hub.hubService.integrations.nearby
    : null

  // Engine state, read under the names the view already used. A view with no
  // engine says so rather than rendering an empty page.
  readonly property bool backendReady: engine ? engine.backendReady : false
  readonly property bool receiverEnabled: engine ? engine.receiverEnabled : false
  readonly property bool discoveryActive: engine ? engine.discoveryActive : false
  readonly property var devices: engine ? engine.devices : []
  readonly property var selectedDevice: engine ? engine.selectedDevice : null
  readonly property string viewState: engine ? engine.viewState : "nearby"
  readonly property string statusText: engine ? engine.statusText : "Nearby engine is not loaded."
  readonly property string errorText: engine ? engine.errorText : "Nearby engine is not loaded."
  readonly property var incomingQueue: engine ? engine.incomingQueue : []
  readonly property var incoming: engine ? engine.incoming : null
  readonly property string incomingText: engine ? engine.incomingText : ""
  readonly property real progress: engine ? engine.progress : 0
  readonly property string transferName: engine ? engine.transferName : ""
  readonly property string transferPeer: engine ? engine.transferPeer : ""
  readonly property string pinError: engine ? engine.pinError : ""

  // Cursor state is this view's own.
  property int selectedIndex: 0
  property bool cursorActive: false
  property int nearbyPhraseIndex: 0
  property bool viewRegistered: false
  property bool shown: false

  readonly property var nearbyPhrases: [
    "Looking nearby",
    "Finding devices",
    "Listening locally",
    "Ready to receive",
    "Watching the LAN",
    "Checking the air"
  ]
  readonly property bool rotatingPhrases: shown && receiverEnabled && backendReady && viewState === "nearby" && errorText === ""
  readonly property string heroMetaText: {
    if (viewState === "nearby") {
      if (!receiverEnabled) return "Turned off"
      if (!backendReady) return errorText || statusText
      return nearbyPhrases[nearbyPhraseIndex % nearbyPhrases.length]
    }
    if (viewState === "target") return "Choose what to send"
    return statusText
  }

  readonly property bool keysBlocked: viewState === "pin" && pinInput.activeFocus

  implicitHeight: content.implicitHeight

  // ---- Tab contract: lifecycle. Discovery follows the page being looked at,
  //      and the engine counts open views, so a tab switch has to register
  //      and deregister exactly like opening and closing a popup did.
  function tabShown() {
    shown = true
    cursorActive = false
    selectedIndex = -1
    nearbyPhraseIndex = 0
    syncViewState()
    Qt.callLater(function() {
      if (root.viewState === "pin") pinInput.forceActiveFocus()
      else if (root.hub && typeof root.hub.focusKeyCatcher === "function") root.hub.focusKeyCatcher()
    })
  }

  function tabHidden() {
    shown = false
    syncViewState()
  }

  function syncViewState() {
    if (!engine || shown === viewRegistered) return
    viewRegistered = shown
    if (shown) engine.viewOpened()
    else engine.viewClosed()
  }

  onEngineChanged: { viewRegistered = false; syncViewState() }
  Component.onDestruction: if (engine && viewRegistered) engine.viewClosed()

  function panelClosed() {
    // tabHidden() already deregisters the view; this only drops the cursor so
    // the page does not reopen with a stale selection.
    cursorActive = false
    selectedIndex = -1
  }

  Connections {
    target: root.engine
    function onCursorRequested(index) { root.selectedIndex = index }
    function onPinCleared() { pinInput.text = "" }
    function onPinFocusRequested() { if (root.shown) Qt.callLater(function() { pinInput.forceActiveFocus() }) }
    function onFocusRestoreRequested() {
      if (root.shown && root.hub && typeof root.hub.focusKeyCatcher === "function") root.hub.focusKeyCatcher()
    }
  }

  function toggleReceiver() { if (engine) engine.toggleReceiver() }
  function startDiscovery() { if (engine) engine.startDiscovery() }
  function forceFullDiscovery() { if (engine) engine.forceFullDiscovery() }
  function chooseDevice(index) { if (engine) engine.chooseDevice(index) }
  function acceptIncoming() { if (engine) engine.acceptIncoming() }
  function declineIncoming() { if (engine) engine.declineIncoming() }
  function finishText() { if (engine) engine.finishText() }
  function finishTerminal() { if (engine) engine.finishTerminal() }
  function cancelOutgoing() { if (engine) engine.cancelOutgoing() }
  function cancelPin() { if (engine) engine.cancelPin() }
  function retryWithPin() { if (engine) engine.retryWithPin(String(pinInput.text || "")) }
  function failWith(message) { if (engine) engine.failWith(message) }
  function noteTextCopied() { if (engine) engine.noteTextCopied() }
  function beginOutgoing(pending) { if (engine) engine.beginOutgoing(pending) }

  // Escape unwinds the view's own depth first — a PIN prompt, a chosen
  // target — and only then falls through to the panel closing.
  function handleClose() {
    if (viewState === "pin") { cancelPin(); return true }
    if (viewState === "target") {
      if (engine) engine.clearTarget()
      return true
    }
    return false
  }

  // The chooser and the clipboard belong to the monitor the user acted on, so
  // they stay with the view and hand their result to the engine.
  function selectFiles() { if (!selectedDevice || picker.running) return; picker.device = selectedDevice; picker.launched = false; picker.running = true }
  function sendClipboard() { if (!selectedDevice || clipboard.running) return; clipboard.device = selectedDevice; clipboard.launched = false; clipboard.running = true }
  function copyReceivedText() { if (clipboardWriter.running || root.viewState !== "text") return; clipboardWriter.value = root.incomingText; clipboardWriter.launched = false; clipboardWriter.running = true }

  function handleMove(dx, dy) {
    cursorActive = true
    if (viewState === "nearby") {
      if (dy !== 0) selectedIndex = Math.max(-1, Math.min(devices.length, selectedIndex + dy))
      return true
    }
    var count = viewState === "target" ? 2 : ((viewState === "incoming" || viewState === "text") ? 2 : 1)
    if (count > 0 && dy !== 0) selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + dy))
    return true
  }

  function handleActivate() {
    if (viewState === "nearby") {
      if (selectedIndex < 0) toggleReceiver()
      else if (selectedIndex === devices.length) forceFullDiscovery()
      else chooseDevice(selectedIndex)
    }
    else if (viewState === "target") selectedIndex === 0 ? selectFiles() : sendClipboard()
    else if (viewState === "incoming") selectedIndex === 0 ? declineIncoming() : acceptIncoming()
    else if (viewState === "text") { if (selectedIndex === 0) copyReceivedText(); else finishText() }
    else if (viewState === "sending") cancelOutgoing()
    else if (viewState === "success" || viewState === "error") finishTerminal()
    return true
  }

  Timer {
    id: nearbyPhraseTimer
    interval: 2800
    running: root.rotatingPhrases
    repeat: true
    onTriggered: nearbyPhraseSwap.restart()
  }

  SequentialAnimation {
    id: nearbyPhraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.nearbyPhraseIndex = (root.nearbyPhraseIndex + 1) % root.nearbyPhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  onRotatingPhrasesChanged: {
    if (!rotatingPhrases) {
      nearbyPhraseSwap.stop()
      hero.metaOpacity = 1.0
    }
  }

  // Quickshell reports a command it could not launch by returning `running` to
  // false without ever emitting `started` or `exited`, so a missing binary has
  // to be caught there. Exit codes never carry that news: nothing runs a shell
  // on our behalf, so the 127 a shell would report cannot reach us.
  Process {
    id: picker
    property var device: null
    property bool launched: false
    command: ["omarchy-file-select", "--title", "Send nearby", "--multiple"]
    running: false
    stdout: StdioCollector { id: pickerOutput; waitForEnd: true }
    onStarted: picker.launched = true
    onRunningChanged: if (!running && !picker.launched) root.failWith("The file chooser could not be started")
    onExited: function(code) {
      // The chooser separates a decision from a fault: 1 is nobody picking
      // anything, and anything above it is a chooser that never opened.
      if (code > 1) { root.failWith("The file chooser did not open"); return }
      if (code !== 0 || !root.selectedDevice || !device || root.selectedDevice.fingerprint !== device.fingerprint || root.viewState !== "target") return
      var paths = String(pickerOutput.text || "").split("\n").filter(function(v) { return v.trim() !== "" })
      if (paths.length) root.beginOutgoing({ kind: "files", device: device, paths: paths })
    }
  }

  Process {
    id: clipboard
    property var device: null
    property bool launched: false
    command: ["wl-paste", "--no-newline", "--type", "text"]
    running: false
    stdout: StdioCollector { id: clipboardOutput; waitForEnd: true }
    onStarted: clipboard.launched = true
    onRunningChanged: if (!running && !clipboard.launched) root.failWith("wl-paste is required to read the clipboard")
    onExited: function(code) {
      if (!root.selectedDevice || !device || root.selectedDevice.fingerprint !== device.fingerprint || root.viewState !== "target") return
      var text = String(clipboardOutput.text || "")
      if (code === 0 && text.trim() !== "") root.beginOutgoing({ kind: "text", device: device, text: text })
      else root.failWith("Clipboard is empty")
    }
  }

  Process {
    id: clipboardWriter
    property string value: ""
    property bool launched: false
    command: ["wl-copy"]
    running: false
    stdinEnabled: true
    onStarted: { clipboardWriter.launched = true; write(value); stdinEnabled = false }
    onRunningChanged: if (!running && !clipboardWriter.launched && root.viewState === "text") root.failWith("wl-copy is required to copy received text")
    onExited: function(code) {
      stdinEnabled = true
      if (root.viewState !== "text") return
      if (code === 0) root.noteTextCopied()
      else root.failWith("wl-copy is required to copy received text")
    }
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(12)

    Rectangle {
      width: parent.width
      height: hero.implicitHeight + Style.space(32)
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
      PanelHero {
        x: Style.space(16)
        y: Style.space(16)
        width: parent.width - Style.space(32)
        id: hero
        title: (root.viewState === "target" || root.viewState === "pin") && root.selectedDevice ? root.selectedDevice.alias : (root.viewState === "incoming" ? "Incoming" : "Nearby")
        meta: root.heroMetaText
        detail: ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconComponent: Component { Text { text: root.viewState === "incoming" ? "󰁅" : "󰀂"; color: root.incoming ? root.urgent : root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.display } }
        trailingControl: root.viewState === "nearby" && root.engine ? receiverToggle : null
      }
    }

    Component {
      id: receiverToggle
      ToggleSwitch {
        checked: root.receiverEnabled
        hasCursor: root.cursorActive && root.selectedIndex < 0
        foreground: root.foreground
        onHovered: function(on) { if (on) { root.cursorActive = true; root.selectedIndex = -1 } }
        onToggled: root.toggleReceiver()
        PanelToolTip { visible: parent.containsMouse; text: root.receiverEnabled ? "Turn Nearby off" : "Turn Nearby on"; fontFamily: root.fontFamily }
      }
    }

    PanelSeparator { width: parent.width }

    IntegrationSetup {
      visible: !root.engine
      width: parent.width
      pluginId: "oma.nearby"
      actionText: "Enable nearby sharing"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Column {
      visible: !!root.engine && (root.engine.helperUpdateOffered || root.engine.helperUpdating)
      width: parent.width
      spacing: Style.space(8)
      Button {
        text: root.engine && root.engine.helperUpdating ? "Updating…" : "Update Nearby"
        enabled: !!root.engine && !root.engine.helperUpdating
        foreground: root.foreground
        onClicked: root.engine.startHelperUpdate()
      }
      Text {
        width: parent.width
        text: root.engine ? root.engine.helperUpdateError || root.engine.helperUpdateStatus : ""
        visible: text !== ""
        wrapMode: Text.Wrap
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Column {
      visible: !!root.engine && root.viewState === "nearby"; width: parent.width; spacing: Style.space(4)
      PanelSectionHeader { text: "NEARBY"; foreground: root.foreground; fontFamily: root.fontFamily }
      Text { visible: root.devices.length === 0; width: parent.width; textFormat: Text.PlainText; text: !root.receiverEnabled ? "Nearby is turned off" : (root.discoveryActive ? "Finding devices…" : (root.backendReady ? "No devices nearby" : root.errorText)); wrapMode: Text.Wrap; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body; topPadding: Style.space(12); bottomPadding: Style.space(12) }
      Repeater {
        model: root.devices
        Button { required property var modelData; required property int index; width: parent.width; leftAlign: true; bordered: false; iconText: Model.iconFor(modelData.deviceType); text: modelData.alias; foreground: root.foreground; fontFamily: root.fontFamily; hasCursor: root.cursorActive && root.selectedIndex === index; onHovered: function(v) { if (v) { root.cursorActive = true; root.selectedIndex = index } }; onClicked: root.chooseDevice(index) }
      }
      Button { visible: root.receiverEnabled && root.backendReady; width: parent.width; leftAlign: true; bordered: false; iconText: "󰑐"; text: "Search for new devices"; foreground: root.foreground; fontFamily: root.fontFamily; hasCursor: root.cursorActive && root.selectedIndex === root.devices.length; onHovered: function(v) { if (v) { root.cursorActive = true; root.selectedIndex = root.devices.length } }; onClicked: root.forceFullDiscovery() }
    }

    Column {
      visible: root.viewState === "target"; width: parent.width; spacing: Style.space(6)
      PanelSectionHeader { text: "SEND"; foreground: root.foreground; fontFamily: root.fontFamily }
      Button { width: parent.width; leftAlign: true; iconText: "󰈔"; text: "Send files"; foreground: root.foreground; fontFamily: root.fontFamily; hasCursor: root.cursorActive && root.selectedIndex === 0; onHovered: function(v) { if (v) { root.cursorActive = true; root.selectedIndex = 0 } }; onClicked: root.selectFiles() }
      Button { width: parent.width; leftAlign: true; iconText: "󰅇"; text: "Send clipboard"; foreground: root.foreground; fontFamily: root.fontFamily; hasCursor: root.cursorActive && root.selectedIndex === 1; onHovered: function(v) { if (v) { root.cursorActive = true; root.selectedIndex = 1 } }; onClicked: root.sendClipboard() }
    }

    Column {
      visible: root.viewState === "pin"; width: parent.width; spacing: Style.space(8)
      PanelSectionHeader { text: "RECEIVER PIN"; foreground: root.foreground; fontFamily: root.fontFamily }
      Text { width: parent.width; text: "This receiver requires a PIN"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      TextField {
        id: pinInput; width: parent.width; password: true; placeholderText: "PIN"; maximumLength: 32; foreground: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body
        inputMethodHints: Qt.ImhDigitsOnly
        validator: RegularExpressionValidator { regularExpression: /[0-9]*/ }
        onAccepted: root.retryWithPin()
        Keys.onPressed: function(event) { if (event.key === Qt.Key_Escape) { root.cancelPin(); event.accepted = true } }
      }
      Text { visible: root.pinError !== ""; width: parent.width; text: root.pinError; color: root.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      Row { width: parent.width; spacing: Style.space(8)
        Button { width: (parent.width - parent.spacing) / 2; text: "Cancel"; bordered: true; foreground: root.dim; onClicked: root.cancelPin() }
        Button { width: (parent.width - parent.spacing) / 2; text: "Retry"; bordered: true; foreground: root.foreground; onClicked: root.retryWithPin() }
      }
    }

    Column {
      visible: root.viewState === "incoming" && root.incoming; width: parent.width; spacing: Style.space(8)
      Text { width: parent.width; textFormat: Text.PlainText; text: root.incoming ? root.incoming.sender + " wants to send" : ""; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
      Text { width: parent.width; textFormat: Text.PlainText; text: root.incoming ? Model.incomingSummary(root.incoming.files) + " · " + Model.formatBytes(root.incoming.total) : ""; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
      Text { visible: root.incomingQueue.length > 1; width: parent.width; text: (root.incomingQueue.length - 1) + (root.incomingQueue.length === 2 ? " more request" : " more requests"); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      Row { width: parent.width; spacing: Style.space(8)
        Button { width: (parent.width - parent.spacing) / 2; text: "Decline"; foreground: root.urgent; bordered: true; hasCursor: root.cursorActive && root.selectedIndex === 0; onClicked: root.declineIncoming() }
        Button { width: (parent.width - parent.spacing) / 2; text: "Accept"; foreground: root.foreground; bordered: true; hasCursor: root.cursorActive && root.selectedIndex === 1; onClicked: root.acceptIncoming() }
      }
    }

    Column {
      visible: root.viewState === "sending" || root.viewState === "receiving"; width: parent.width; spacing: Style.space(8)
      PanelSectionHeader { text: root.viewState === "sending" ? "SENDING" : "RECEIVING"; foreground: root.foreground; fontFamily: root.fontFamily }
      Text { width: parent.width; textFormat: Text.PlainText; text: root.transferName; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true; elide: Text.ElideMiddle }
      Rectangle { width: parent.width; height: Style.space(4); radius: Math.min(height / 2, Style.cornerRadius); color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.38); Rectangle { width: parent.width * Math.max(0, Math.min(1, root.progress)); height: parent.height; radius: parent.radius; color: root.foreground; Behavior on width { NumberAnimation { duration: 120 } } } }
      Text { text: Math.round(root.progress * 100) + "% · " + (root.viewState === "sending" ? "to " : "from ") + root.transferPeer; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      Button { visible: root.viewState === "sending"; text: "Cancel"; bordered: true; foreground: root.urgent; hasCursor: root.cursorActive; onClicked: root.cancelOutgoing() }
    }

    Column {
      visible: root.viewState === "success" || root.viewState === "error"; width: parent.width; spacing: Style.space(8)
      Text { width: parent.width; textFormat: Text.PlainText; text: root.viewState === "success" ? root.statusText : root.errorText; wrapMode: Text.Wrap; color: root.viewState === "error" ? root.urgent : root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
      Text { visible: root.viewState === "success"; width: parent.width; textFormat: Text.PlainText; text: root.transferPeer !== "" ? (root.statusText === "Sent" ? "to " : "from ") + root.transferPeer : ""; wrapMode: Text.Wrap; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      Button { text: "Done"; bordered: true; foreground: root.foreground; hasCursor: root.cursorActive; onClicked: root.finishTerminal() }
    }

    Column {
      visible: root.viewState === "text"; width: parent.width; spacing: Style.space(8)
      PanelSectionHeader { text: "RECEIVED TEXT"; foreground: root.foreground; fontFamily: root.fontFamily }
      Text { width: parent.width; textFormat: Text.PlainText; text: root.incomingText; wrapMode: Text.Wrap; maximumLineCount: 6; elide: Text.ElideRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      Row { width: parent.width; spacing: Style.space(8)
        Button { width: (parent.width - parent.spacing) / 2; text: "Copy"; iconText: "󰆏"; bordered: true; foreground: root.foreground; hasCursor: root.cursorActive && root.selectedIndex === 0; onClicked: { root.copyReceivedText() } }
        Button { width: (parent.width - parent.spacing) / 2; text: "Done"; bordered: true; foreground: root.foreground; hasCursor: root.cursorActive && root.selectedIndex === 1; onClicked: root.finishText() }
      }
    }
  }
}
