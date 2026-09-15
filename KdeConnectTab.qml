import QtQuick
import qs.Commons
import qs.Ui
import "kdeconnect"

// KDE Connect page of the hub: devices, pairing, the action toolbar, the
// ping/share composers, and remote commands.
//
// The four sections under kdeconnect/ are omaconnect's, copied verbatim —
// see kdeconnect/VENDORED.md for the revision and how to resync. They take a
// `panel` object and read their whole state off it, so what this file is, is
// that object: the state machine from upstream's Panel.qml at the same
// revision, plus the hub's tab contract on top.
//
// Copied rather than imported across plugins, because `panel.*` is
// upstream's internal contract and a release is free to change it. The engine remains installed upstream and is loaded once by
// HubIntegrations.qml, within the Hub service.
Item {
  id: root

  // ---- Tab contract, injected by Panel.qml.
  property var hub: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // ---- The surface the vendored sections bind to. Names are upstream's;
  //      changing one breaks them.
  readonly property var service: hub && hub.hubService && hub.hubService.integrations
    ? hub.hubService.integrations.phone
    : null
  readonly property var device: service ? service.selectedDevice : null
  readonly property string deviceName: device && typeof device.name === "string" ? device.name : "KDE Connect"
  readonly property string deviceId: device ? String(device.id || "") : ""
  onDeviceIdChanged: {
    if (unpairConfirmingId) cancelUnpairConfirm(unpairConfirmingId)
    resetComposer()
    commandsExpanded = false
    commandSelectedIndex = 0
    focusSection = "devices"
  }

  property string activeComposer: "none"
  property string draftPing: ""
  property string draftText: ""
  property string composerError: ""
  property string focusSection: "devices"
  property int selectedIndex: 0
  property int actionSelectedIndex: 0
  property bool cursorActive: false
  property bool commandsExpanded: false
  property int commandSelectedIndex: 0
  property string unpairConfirmingId: ""

  readonly property var availableActions: {
    if (!root.device || !root.device.paired || !root.device.reachable) return []
    var caps = root.device.capabilities || {}
    var res = []
    if (caps.ring) res.push("ring")
    if (caps.clipboard) res.push("clipboard")
    if (caps.file) res.push("file")
    if (caps.sms) res.push("sms")
    if (caps.ping) res.push("ping")
    if (caps.text) res.push("text")
    return res
  }

  // A phone going unreachable takes its actions with it; the cursor must not
  // be left sitting on a row that is no longer drawn.
  onAvailableActionsChanged: clampActionIndex()

  function clampActionIndex() {
    var acts = root.availableActions
    if (acts.length > 0) {
      actionSelectedIndex = Math.max(0, Math.min(acts.length - 1, actionSelectedIndex))
    } else {
      actionSelectedIndex = 0
      if (focusSection === "actions") focusSection = "devices"
    }
    if (activeComposer !== "none" && acts.indexOf(activeComposer) < 0) {
      resetComposer()
      focusSection = "devices"
      if (hub) hub.focusKeyCatcher()
    }
  }

  implicitHeight: contentColumn.implicitHeight

  // ---- Tab contract: the composers take the keyboard whole while open.
  readonly property bool keysBlocked: root.activeComposer !== "none"
    || !!(composerSection
      && ((composerSection.pingInput && composerSection.pingInput.activeFocus)
        || (composerSection.textInput && composerSection.textInput.activeFocus)))

  function triggerAction(actionId) {
    if (!service || !device) return
    if (actionId === "ring") service.ringDevice(device.id)
    else if (actionId === "clipboard") service.sendClipboard(device.id)
    else if (actionId === "file") service.startFileSelection(device.id)
    else if (actionId === "sms") service.openSmsApp(device.id)
    else if (actionId === "ping") {
      if (activeComposer === "ping") closeComposer()
      else openComposer("ping")
    } else if (actionId === "text") {
      if (activeComposer === "text") closeComposer()
      else openComposer("text")
    }
  }

  function requestUnpairConfirm(id) {
    unpairConfirmingId = id
    if (service && typeof service.setPendingPairing === "function") service.setPendingPairing(id, "unpair_confirm")
  }

  function cancelUnpairConfirm(id) {
    if (!id || unpairConfirmingId === id) unpairConfirmingId = ""
    if (service && id && typeof service.setPendingPairing === "function") service.setPendingPairing(id, "")
  }

  function selectDevice(id) {
    if (!service) return
    if (unpairConfirmingId && unpairConfirmingId !== id) cancelUnpairConfirm(unpairConfirmingId)
    unpairConfirmingId = ""
    service.selectDevice(id)
    // Clicking a device moves the keyboard cursor onto it too, so the two
    // never disagree about which row is current.
    var list = service.devices || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === String(id)) {
        selectedIndex = i
        break
      }
    }
    clampActionIndex()
  }

  function confirmUnpair(id) {
    unpairConfirmingId = ""
    if (service) service.unpairDevice(id)
  }

  function openComposer(type) {
    composerError = ""
    activeComposer = type
    if (type === "ping") {
      focusSection = "ping"
      Qt.callLater(function() { if (composerSection && composerSection.pingInput) composerSection.pingInput.forceActiveFocus() })
    } else if (type === "text") {
      focusSection = "text"
      Qt.callLater(function() { if (composerSection && composerSection.textInput) composerSection.textInput.forceActiveFocus() })
    }
  }

  function closeComposer() {
    activeComposer = "none"
    composerError = ""
    focusSection = "actions"
    // The panel owns the key catcher now, not this page.
    if (hub && typeof hub.focusKeyCatcher === "function") hub.focusKeyCatcher()
  }

  function resetComposer() {
    activeComposer = "none"
    draftPing = ""
    draftText = ""
    composerError = ""
  }

  function submitPing() {
    var val = draftPing.trim()
    if (!val) {
      composerError = "Message cannot be empty"
      if (service) {
        service.actionState = "blocked"
        service.actionError = "Message cannot be empty"
        service.actionMessage = ""
      }
      return false
    }
    if (service && device) {
      var success = service.pingDevice(device.id, val)
      if (success) {
        draftPing = ""
        closeComposer()
      } else {
        composerError = (service && service.actionError) ? service.actionError : "Failed to send ping"
      }
      return success
    }
    composerError = "Service unavailable"
    return false
  }

  function submitText() {
    var val = draftText.trim()
    if (!val) {
      composerError = "Message cannot be empty"
      if (service) {
        service.actionState = "blocked"
        service.actionError = "Message cannot be empty"
        service.actionMessage = ""
      }
      return false
    }
    if (service && device) {
      var success = service.shareText(device.id, val)
      if (success) {
        draftText = ""
        closeComposer()
      } else {
        composerError = (service && service.actionError) ? service.actionError : "Failed to share text"
      }
      return success
    }
    composerError = "Service unavailable"
    return false
  }

  function select(delta) {
    var list = service ? service.devices : []
    if (!list.length) return
    selectedIndex = Math.max(0, Math.min(list.length - 1, selectedIndex + delta))
    if (cursorActive) selectDevice(list[selectedIndex].id)
  }

  function toggleCommandsExpanded() {
    commandsExpanded = !commandsExpanded
    if (commandsExpanded && service && device && device.capabilities && device.capabilities.commands)
      service.fetchRemoteCommands(device.id)
  }

  function selectCommand(delta) {
    var list = remoteCommands()
    if (!list.length) return
    commandSelectedIndex = Math.max(0, Math.min(list.length - 1, commandSelectedIndex + delta))
  }

  function remoteCommands() {
    return (service && service.remoteCommands) ? service.remoteCommands : []
  }

  function hasCommands() {
    return !!(root.device && root.device.capabilities && root.device.capabilities.commands)
  }

  // ---- Tab contract: keyboard.
  //
  // Upstream keeps this navigation in its text-key handler, where none of it
  // can run: PanelKeyCatcher turns h/j/k/l into move events before any text
  // key is emitted, and arrow keys carry no text at all, so its panel is left
  // with a cursor that lights up and then will not move. Ported here as the
  // move handler it was written to be.
  function handleMove(dx, dy) {
    // The first press only lights the cursor, so arrowing into the page does
    // not also act on whatever happened to be selected.
    if (!root.cursorActive) {
      root.cursorActive = true
      return true
    }

    if (dy > 0) moveDown()
    else if (dy < 0) moveUp()

    if (dx > 0) moveRight()
    else if (dx < 0) moveLeft()

    return true
  }

  function moveDown() {
    if (focusSection === "commands") {
      if (commandsExpanded) {
        var cmds = remoteCommands()
        if (cmds.length > 0 && commandSelectedIndex < cmds.length - 1) selectCommand(1)
        else focusSection = "devices"
      } else {
        focusSection = "devices"
      }
      return
    }
    if (focusSection === "actions") {
      var acts = root.availableActions
      if (acts.length > 0 && actionSelectedIndex < acts.length - 1) actionSelectedIndex++
      else if (hasCommands()) focusSection = "commands"
      else focusSection = "devices"
      return
    }
    select(1)
  }

  function moveUp() {
    var acts = root.availableActions
    if (focusSection === "commands") {
      if (commandsExpanded && commandSelectedIndex > 0) {
        selectCommand(-1)
      } else if (acts.length > 0) {
        focusSection = "actions"
        actionSelectedIndex = acts.length - 1
      } else {
        focusSection = "devices"
      }
      return
    }
    if (focusSection === "actions") {
      if (actionSelectedIndex > 0) actionSelectedIndex--
      else focusSection = "devices"
      return
    }
    select(-1)
  }

  function moveRight() {
    var acts = root.availableActions
    if (focusSection === "devices") {
      if (acts.length > 0) {
        focusSection = "actions"
        actionSelectedIndex = 0
      } else if (hasCommands()) {
        focusSection = "commands"
      }
      return
    }
    if (focusSection === "actions") {
      if (actionSelectedIndex < acts.length - 1) actionSelectedIndex++
      else if (hasCommands()) focusSection = "commands"
      else focusSection = "devices"
      return
    }
    if (focusSection === "commands") focusSection = "devices"
  }

  function moveLeft() {
    var acts = root.availableActions
    if (focusSection === "commands") {
      if (acts.length > 0) {
        focusSection = "actions"
        actionSelectedIndex = acts.length - 1
      } else {
        focusSection = "devices"
      }
      return
    }
    if (focusSection === "actions") {
      if (actionSelectedIndex > 0) actionSelectedIndex--
      else focusSection = "devices"
      return
    }
    if (focusSection === "devices") {
      if (hasCommands()) {
        focusSection = "commands"
      } else if (acts.length > 0) {
        focusSection = "actions"
        actionSelectedIndex = acts.length - 1
      }
    }
  }

  function handleActivate() {
    if (focusSection === "devices") {
      var list = service ? service.devices : []
      var dev = list[selectedIndex]
      if (dev && service) {
        selectDevice(dev.id)
        var pending = (service.pendingPairing && service.pendingPairing[dev.id]) ? service.pendingPairing[dev.id] : ""
        if (root.unpairConfirmingId === dev.id || pending === "unpair_confirm") {
          root.confirmUnpair(dev.id)
        } else if (!dev.paired) {
          // Enter on a request already in flight takes it back, rather than
          // being a key that does nothing for as long as the request hangs.
          if (pending === "requesting") {
            service.setPendingPairing(dev.id, "")
            if (typeof service.clearActionState === "function") service.clearActionState()
          } else {
            service.pairDevice(dev.id)
          }
        } else if (pending !== "removing") {
          if (root.availableActions.length > 0) { root.focusSection = "actions"; root.actionSelectedIndex = 0 }
          else if (root.hasCommands()) root.focusSection = "commands"
        }
      }
    } else if (focusSection === "refresh") {
      if (service) service.refresh(true)
    } else if (focusSection === "actions") {
      var acts = availableActions
      if (acts.length > 0) triggerAction(acts[Math.max(0, Math.min(acts.length - 1, actionSelectedIndex))])
    } else if (focusSection === "ring" && service && device) {
      service.ringDevice(device.id)
    } else if (focusSection === "clipboard" && service && device) {
      service.sendClipboard(device.id)
    } else if (focusSection === "file" && service && device) {
      service.startFileSelection(device.id)
    } else if (focusSection === "ping") {
      if (activeComposer === "ping") submitPing()
      else openComposer("ping")
    } else if (focusSection === "text") {
      if (activeComposer === "text") submitText()
      else openComposer("text")
    } else if (focusSection === "commands" && service && device) {
      if (!commandsExpanded) {
        toggleCommandsExpanded()
      } else if (remoteCommands().length > 0) {
        var cmds = remoteCommands()
        var cmd = cmds[Math.max(0, Math.min(cmds.length - 1, commandSelectedIndex))]
        if (cmd) service.executeRemoteCommand(device.id, cmd.key)
      } else {
        service.fetchRemoteCommands(device.id)
      }
    }
    return true
  }

  function handleTextKey(t) {
    if (!root.service && String(t).toLowerCase() === "a") { phoneSetup.activate(); return true }
    if (root.activeComposer !== "none") return false
    var key = String(t).toLowerCase()

    if (key === "r") {
      if (service) service.refresh(true)
      return true
    }

    if (key === "p" && focusSection === "devices") {
      var devP = deviceAtCursor()
      if (devP && !devP.paired && service) {
        var pendP = pendingFor(devP.id)
        if (pendP !== "requesting") service.pairDevice(devP.id)
      }
      return true
    }

    if (key === "u" && focusSection === "devices") {
      var devU = deviceAtCursor()
      if (devU && devU.paired && service) {
        if (pendingFor(devU.id) !== "removing") requestUnpairConfirm(devU.id)
      }
      return true
    }

    if (key === "y" && awaitingUnpairConfirm()) {
      confirmUnpair(root.unpairConfirmingId || service.selectedDeviceId)
      return true
    }

    if (key === "c") return abortPending()

    return false
  }

  // Escape backs out one layer at a time — a confirmation, then a composer —
  // and only closes the panel once there is nothing left to back out of.
  function handleClose() {
    if (root.unpairConfirmingId) {
      cancelUnpairConfirm(root.unpairConfirmingId)
      return true
    }
    if (root.activeComposer !== "none") {
      closeComposer()
      return true
    }
    return false
  }

  function abortPending() {
    var target = root.unpairConfirmingId || (service ? service.selectedDeviceId : "")
    if (!target || !service) return false
    if (root.unpairConfirmingId || pendingFor(target) === "unpair_confirm") {
      cancelUnpairConfirm(target)
      return true
    }
    if (pendingFor(target) === "requesting") {
      service.setPendingPairing(target, "")
      if (typeof service.clearActionState === "function") service.clearActionState()
      return true
    }
    return false
  }

  function pendingFor(id) {
    if (!service || !service.pendingPairing || !id) return ""
    return service.pendingPairing[id] || ""
  }

  function deviceAtCursor() {
    var list = service ? service.devices : []
    return list[selectedIndex]
  }

  function awaitingUnpairConfirm() {
    if (!service || !service.selectedDeviceId) return false
    var id = service.selectedDeviceId
    if (root.unpairConfirmingId === id) return true
    return pendingFor(id) === "unpair_confirm"
  }

  function refresh() {
    if (service) service.refresh(false)
  }

  function panelClosed() {
    // A confirmation must not survive to greet whoever opens the page next.
    if (root.unpairConfirmingId) cancelUnpairConfirm(root.unpairConfirmingId)
    resetComposer()
    root.cursorActive = false
  }

  Column {
    id: contentColumn
    width: parent.width
    spacing: Style.space(12)

    Column {
      visible: !root.service
      width: parent.width
      spacing: Style.space(16)
      Text {
        text: "Connect your phone"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }
      Text {
        width: parent.width
        text: phoneSetup.configuredEnabled ? "Loading your devices…" : "Enable phone integration, then open KDE Connect on your phone. Keep both devices on the same network to pair them."
        wrapMode: Text.WordWrap
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      IntegrationSetup {
        id: phoneSetup
        width: parent.width
        pluginId: "omaconnect"
        actionText: "Enable phone integration"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }

    Rectangle {
      visible: !!root.service
      width: parent.width
      height: deviceSection.implicitHeight + Style.space(32)
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
      DeviceSection {
        id: deviceSection
        x: Style.space(16)
        y: Style.space(16)
        width: parent.width - Style.space(32)
        panel: root
      }
    }

    ActionToolbar {
      id: actionToolbar
      panel: root
    }

    ComposerSection {
      id: composerSection
      panel: root
    }

    RemoteCommandsSection {
      id: remoteCommandsSection
      panel: root
    }
  }
}
