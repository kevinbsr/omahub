import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "MediaModel.js" as MediaModel

// Media page of the hub.
//
// Two layers, deliberately. Transport — play/pause, next, previous — goes
// through the plugin's own Service.qml, so a click here and a media key are
// the same action with the same player ranking behind them. Seeking, volume,
// shuffle and loop have no media key and no service API, so they are set on
// the active player directly.
//
// Position is polled rather than bound: MPRIS does not push it. The poll
// runs only while this page is the one being looked at, which is what
// tabShown/tabHidden are for.
Item {
  id: root

  // ---- Tab contract, injected by Panel.qml.
  property var hub: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.7)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.52)

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("kevin.hub")
    : null

  readonly property var directPlayers: Mpris.players ? Mpris.players.values : []
  property var fallbackPlayer: null

  readonly property var activePlayer: service ? service.activePlayer : selectFallbackPlayer()
  readonly property var sourcePlayers: service ? service.sourcePlayers : directPlayers

  readonly property bool hasPlayer: activePlayer !== null && activePlayer !== undefined
  readonly property bool playing: hasPlayer && activePlayer.isPlaying === true
  readonly property string title: hasPlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: hasPlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: hasPlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: hasPlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string sourceName: hasPlayer ? String(activePlayer.identity || activePlayer.desktopEntry || "") : ""

  readonly property var playerWindow: MediaModel.windowForPlayer(activePlayer, ToplevelManager.toplevels.values)
  readonly property bool canFocusPlayer: hasPlayer && (!!playerWindow || activePlayer.canRaise === true)

  function focusPlayer() {
    if (!canFocusPlayer) return
    var window = playerWindow
    var player = activePlayer
    if (hub) hub.close()
    // Release the panel's keyboard focus before activating the application.
    Qt.callLater(function() {
      if (window) window.activate()
      else if (player && player.canRaise) player.raise()
    })
  }

  // ---- Capability gates. Every control below is drawn only where the
  //      player admits it works; a dead slider is worse than no slider.
  readonly property bool canSeek: hasPlayer && activePlayer.canSeek === true
    && activePlayer.positionSupported === true && duration > 0
  readonly property real duration: (hasPlayer && activePlayer.lengthSupported && activePlayer.length > 0)
    ? activePlayer.length : 0
  // Volume goes through PipeWire, not MPRIS.
  //
  // Chromium advertises the MPRIS Volume property and then discards writes to
  // it — measured: setting 0.35 leaves it reading 1.0 and the audio untouched.
  // The stream volume is the real one, it always works, and using it here
  // makes this slider and the active source's row in the list the same
  // number instead of two that disagree. MPRIS is kept only for a player with
  // no live stream to point at.
  readonly property var activeStreams: streamsFor(activePlayer)
  readonly property bool hasStreamVolume: activeStreams.length > 0
  readonly property bool hasVolume: hasStreamVolume || (hasPlayer && activePlayer.volumeSupported === true)
  readonly property real volumeValue: hasStreamVolume
    ? appVolume(activeStreams)
    : (hasPlayer ? activePlayer.volume : 0)
  readonly property bool volumeMuted: hasStreamVolume
    ? appMuted(activeStreams)
    : (hasPlayer && activePlayer.volume <= 0.001)
  readonly property bool hasShuffle: hasPlayer && activePlayer.shuffleSupported === true
  readonly property bool hasLoop: hasPlayer && activePlayer.loopSupported === true

  // Polled, not bound. Reset on a track change so the bar never shows the
  // last song's progress against the new song's length.
  property real elapsed: 0
  property bool shown: false
  property bool showRemaining: true

  readonly property string trackKey: hasPlayer
    ? String(activePlayer.trackTitle || "") + "\u001f" + String(activePlayer.trackAlbum || "")
    : ""
  onTrackKeyChanged: syncPosition()

  // Keyboard cursor over the source list. -1 means the cursor is on the
  // transport, which is where it starts: the common case is one source and
  // a play/pause, not picking between four players.
  property int cursorIndex: -1

  implicitHeight: column.implicitHeight

  // ---- Tab contract: lifecycle. Nothing here polls while the page is not
  //      the one on screen.
  function tabShown() {
    shown = true
    cursorIndex = -1
    syncPosition()
  }

  function tabHidden() { shown = false }
  function refresh() { cursorIndex = -1; syncPosition() }
  function panelClosed() { cursorIndex = -1 }

  function syncPosition() {
    elapsed = (hasPlayer && activePlayer.positionSupported) ? (activePlayer.position || 0) : 0
  }

  Timer {
    // Half a second reads as continuous once the fill animates between
    // samples, and halves the DBus traffic a quarter-second poll would make
    // across every monitor's copy of this page. A paused player only needs
    // to be re-read often enough to catch a seek from somewhere else.
    interval: root.playing ? 500 : 2000
    running: root.shown && root.hasPlayer
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!seekBar.dragging) root.syncPosition()
  }

  function playerKey(player) {
    return service ? service.playerKey(player) : MediaModel.playerKey(player)
  }

  function labelFor(player) {
    return MediaModel.labelFor(player) || "Media source"
  }

  // Without the service there is no ranking to inherit, so this is the
  // short version of it: whatever is playing, else whatever has a track,
  // else whatever is there.
  function selectFallbackPlayer() {
    if (fallbackPlayer && directPlayers.indexOf(fallbackPlayer) !== -1) return fallbackPlayer
    for (var i = 0; i < directPlayers.length; i++)
      if (directPlayers[i] && directPlayers[i].isPlaying) return directPlayers[i]
    for (var j = 0; j < directPlayers.length; j++) {
      var player = directPlayers[j]
      if (player && (player.trackTitle || player.trackArtist)) return player
    }
    return directPlayers.length > 0 ? directPlayers[0] : null
  }

  function runAction(action) {
    // No OSD from in here: the panel is already on screen showing the
    // result, and an overlay on top of it would be the same news twice.
    if (service) {
      service.runAction(action, false)
      return
    }

    var player = root.activePlayer
    if (!player) return
    if (action === "next" && player.canGoNext) player.next()
    else if (action === "previous" && player.canGoPrevious) player.previous()
    else if (action === "playPause") {
      if (player.isPlaying && player.canPause) player.pause()
      else if (!player.isPlaying && player.canPlay) player.play()
      else if (player.canTogglePlaying) player.togglePlaying()
    }
  }

  function selectSource(player) {
    if (!player) return
    if (service) service.selectPlayer(root.playerKey(player))
    else root.fallbackPlayer = player
  }

  function canDo(action) {
    var player = root.activePlayer
    return player ? MediaModel.canHandleAction(player, action) : false
  }

  // ---- Direct controls. No service route exists for these, and no media
  //      key produces them, so they are set on the player itself.
  function seekTo(value) {
    if (!root.canSeek) return
    var next = Math.max(0, Math.min(root.duration, value))
    activePlayer.position = next
    // Set locally too: the slider snaps back to `value` the instant it is
    // released, so the binding has to already carry the new position.
    root.elapsed = next
  }

  function seekBy(delta) {
    if (!root.canSeek) return
    seekTo(root.elapsed + delta)
  }

  property real preMuteVolume: 1

  function setVolume(value) {
    if (root.hasStreamVolume) {
      setAppVolume(root.activeStreams, value)
      return
    }
    if (!root.hasVolume) return
    activePlayer.volume = Math.max(0, Math.min(1, value))
  }

  function adjustVolume(delta) {
    if (root.hasVolume) root.setVolume(Math.max(0, Math.min(1, root.volumeValue + delta)))
  }

  function toggleMute() {
    if (root.hasStreamVolume) {
      toggleAppMute(root.activeStreams)
      return
    }
    if (!root.hasVolume) return
    if (activePlayer.volume > 0.001) {
      preMuteVolume = activePlayer.volume
      setVolume(0)
    } else {
      setVolume(preMuteVolume > 0.001 ? preMuteVolume : 1)
    }
  }

  function toggleShuffle() {
    if (!root.hasShuffle) return
    activePlayer.shuffle = !activePlayer.shuffle
  }

  // Off, then the whole playlist, then the one track — the order every other
  // player cycles in, so the button does what the muscle expects.
  function cycleLoop() {
    if (!root.hasLoop) return
    var current = activePlayer.loopState
    if (current === MprisLoopState.None) activePlayer.loopState = MprisLoopState.Playlist
    else if (current === MprisLoopState.Playlist) activePlayer.loopState = MprisLoopState.Track
    else activePlayer.loopState = MprisLoopState.None
  }

  // Guarded: these evaluate on every player change, including the moment
  // the last player disappears and activePlayer is briefly null.
  readonly property string loopIcon: {
    if (!hasPlayer) return "󰑖"
    if (activePlayer.loopState === MprisLoopState.Track) return "󰑘"
    return "󰑖"
  }
  readonly property bool loopActive: hasPlayer && hasLoop && activePlayer.loopState !== MprisLoopState.None
  readonly property string loopTooltip: {
    if (!hasPlayer) return "Repeat"
    if (activePlayer.loopState === MprisLoopState.Track) return "Repeating this track"
    if (activePlayer.loopState === MprisLoopState.Playlist) return "Repeating the playlist"
    return "Repeat off"
  }

  // ---- Tab contract: keyboard.
  //
  // Left/right seek rather than skip tracks, the way every player with a
  // scrubber behaves. Skipping keeps `b` and `n`, so nothing was lost — and
  // on a player that cannot seek, left/right fall back to skipping.
  function handleMove(dx, dy) {
    if (dx !== 0) {
      if (root.canSeek) seekBy(dx > 0 ? 5 : -5)
      else runAction(dx > 0 ? "next" : "previous")
    }

    if (dy !== 0) {
      var count = root.sourcePlayers.length
      if (count < 2) return false
      // -1 is a real position (the transport), so the cursor walks
      // [-1, 0 .. count-1] and wraps through it rather than past it.
      var next = root.cursorIndex + dy
      if (next < -1) next = count - 1
      else if (next >= count) next = -1
      root.cursorIndex = next
    }
    return true
  }

  function handleActivate() {
    if (root.cursorIndex >= 0 && root.cursorIndex < root.sourcePlayers.length)
      selectSource(root.sourcePlayers[root.cursorIndex])
    else
      runAction("playPause")
    return true
  }

  function handleTextKey(t) {
    var key = String(t).toLowerCase()
    if (key === "+" || key === "=") adjustVolume(0.05)
    else if (key === "-" || key === "−") adjustVolume(-0.05)
    else if (key === "p") runAction("playPause")
    else if (key === "n") runAction("next")
    else if (key === "b") runAction("previous")
    else if (key === "m") toggleMute()
    else if (key === "o") focusPlayer()
    else if (key === "s") toggleShuffle()
    else if (key === "r") cycleLoop()
    else if (key === "t") root.showRemaining = !root.showRemaining
    else if (key === "e") {
      // Unfold the cursored source's individual streams. Without this the
      // chevron would be the one control on the page a keyboard cannot reach.
      if (cursorIndex < 0 || cursorIndex >= sourcePlayers.length) return false
      toggleExpanded(playerKey(sourcePlayers[cursorIndex]))
    }
    else return false
    return true
  }


  // ---- Per-stream audio. One MPRIS player can own several PipeWire streams:
  //      Chromium opens one per tab that makes sound. They carry no tab
  //      title — every one of them is called "Playback" — so they are
  //      numbered in the order they started and told apart by ear.
  readonly property var playbackStreams: (service && service.playbackStreams) ? service.playbackStreams : []

  function streamsFor(player) {
    return MediaModel.streamsForPlayer(player, root.playbackStreams)
  }

  // The app row reads the loudest of its streams and writes to all of them.
  // Levelling them is the point of a control that says "the browser": a row
  // that only moved one of four would be a worse lie than losing the spread.
  function appVolume(streams) {
    var top = 0
    for (var i = 0; i < streams.length; i++)
      if (streams[i].audio) top = Math.max(top, streams[i].audio.volume)
    return top
  }

  function setAppVolume(streams, value) {
    var next = Math.max(0, Math.min(1.5, value))
    for (var i = 0; i < streams.length; i++)
      if (streams[i].audio) streams[i].audio.volume = next
  }

  function appMuted(streams) {
    if (streams.length === 0) return false
    for (var i = 0; i < streams.length; i++)
      if (streams[i].audio && !streams[i].audio.muted) return false
    return true
  }

  function toggleAppMute(streams) {
    var next = !appMuted(streams)
    for (var i = 0; i < streams.length; i++)
      if (streams[i].audio) streams[i].audio.muted = next
  }

  function setStreamVolume(node, value) {
    if (node && node.audio) node.audio.volume = Math.max(0, Math.min(1.5, value))
  }

  function toggleStreamMute(node) {
    if (node && node.audio) node.audio.muted = !node.audio.muted
  }

  // Which app rows are expanded, keyed by player. Reassigned wholesale so
  // the bindings that read it actually re-evaluate.
  property var expandedSources: ({})

  function isExpanded(key) { return expandedSources[String(key)] === true }

  function toggleExpanded(key) {
    var next = ({})
    for (var k in expandedSources) next[k] = expandedSources[k]
    next[String(key)] = !next[String(key)]
    expandedSources = next
  }

  // Keeps the audio interface of every stream on screen bound and live.
  PwObjectTracker { objects: root.playbackStreams }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(12)

    // The player is one opaque-tint content surface, with the timeline
    // directly below its artwork and metadata. No extra backdrop blur.
    Rectangle {
      width: parent.width
      height: playerContent.implicitHeight + Style.space(32)
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)

      Column {
        id: playerContent
        x: Style.space(16)
        y: Style.space(16)
        width: parent.width - Style.space(32)
        spacing: Style.space(16)

        Item {
          width: parent.width
          height: Math.max(artFrame.height, trackLabels.implicitHeight)

          Rectangle {
            id: artFrame
            width: Style.space(112)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            radius: Style.cornerRadius
            border.width: coverMouse.containsMouse && root.canFocusPlayer ? 1 : 0
            border.color: Color.accent
            Accessible.role: Accessible.Button
            Accessible.name: "Show " + (root.sourceName || "player")
            Accessible.onPressAction: root.focusPlayer()

            MouseArea {
              id: coverMouse
              anchors.fill: parent
              z: 1
              hoverEnabled: true
              enabled: root.canFocusPlayer || root.hasVolume
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) root.toggleMute()
                else root.focusPlayer()
              }
              onWheel: function(wheel) {
                var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y / 120 : wheel.pixelDelta.y / 40
                wheel.accepted = root.hasVolume && delta !== 0
                if (wheel.accepted) root.adjustVolume(delta * 0.05)
              }
              PanelToolTip {
                visible: coverMouse.containsMouse
                text: (root.canFocusPlayer ? "Click: show " + (root.sourceName || "player") + " · O" : "")
                  + (root.hasVolume ? (root.canFocusPlayer ? "\n" : "")
                    + "Scroll: volume · Right-click: mute\n"
                    + (root.volumeMuted ? "Muted" : Math.round(root.volumeValue * 100) + "%") : "")
                fontFamily: root.fontFamily
              }
            }

            Image {
              id: cover
              anchors.fill: parent
              source: root.artUrl
              asynchronous: true
              fillMode: Image.PreserveAspectFit
              visible: status === Image.Ready
            }
            Text {
              anchors.centerIn: parent
              visible: cover.status !== Image.Ready
              text: "󰝚"
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.space(48)
            }
          }

          Column {
            id: trackLabels
            anchors.left: artFrame.right
            anchors.leftMargin: Style.space(20)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Text {
              width: parent.width
              text: root.hasPlayer ? (root.playing ? "NOW PLAYING" : "PAUSED") : "YOUR MUSIC"
              color: root.playing ? Color.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.2
            }
            Text {
              width: parent.width
              text: root.title || (root.hasPlayer ? root.labelFor(root.activePlayer) : "Nothing playing")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(20)
              font.weight: Font.DemiBold
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.artist || (!root.hasPlayer ? "Open a player to start listening." : "")
              visible: text !== ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.album
              visible: text !== ""
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.sourceName
              visible: text !== ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
        // ---- Scrubber, under the buttons that drive it. Present only where the
        //      player reports both a length and the ability to seek, so it never
        //      appears as decoration.
        Item {
          width: parent.width
          visible: root.canSeek
          implicitHeight: visible ? seekBar.implicitHeight + timeRow.implicitHeight : 0

          PanelSlider {
            id: seekBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            bar: root.bar
            minimum: 0
            maximum: Math.max(1, root.duration)
            value: root.elapsed
            step: 5
            onMoved: function(value) { /* preview only; committing every frame fights the player */ }
            onReleased: function(value) { root.seekTo(value) }
          }

          Item {
            id: timeRow
            anchors.top: seekBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: elapsedText.implicitHeight

            Text {
              id: elapsedText
              anchors.left: parent.left
              // While dragging, the number follows the knob rather than the
              // player — otherwise the one readout that says where you are
              // about to land is the one that will not move.
              text: MediaModel.fmtTime(seekBar.dragging ? seekBar.liveValue : root.elapsed)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              text: root.showRemaining
                ? "−" + MediaModel.fmtTime(Math.max(0, root.duration - (seekBar.dragging ? seekBar.liveValue : root.elapsed)))
                : MediaModel.fmtTime(root.duration)
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showRemaining = !root.showRemaining
                PanelToolTip {
                  visible: parent.containsMouse
                  text: root.showRemaining ? "Show total duration · T" : "Show remaining time · T"
                  fontFamily: root.fontFamily
                }
              }
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---- Transport. Shuffle and loop flank the three that every player has,
        //      and drop out entirely on players that do not support them rather
        //      than sitting there greyed.
        Row {
          visible: root.hasPlayer
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Button {
            visible: root.hasShuffle
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒝"
            tooltipText: root.hasPlayer && root.activePlayer.shuffle ? "Shuffling" : "Shuffle off"
            selected: root.hasPlayer && root.activePlayer.shuffle
            foreground: root.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.toggleShuffle()
          }

          Button {
            visible: root.canSeek
            anchors.verticalCenter: parent.verticalCenter
            text: "−10"
            tooltipText: "Back 10 seconds"
            foreground: root.dim
            onClicked: root.seekBy(-10)
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒮"
            tooltipText: "Previous"
            foreground: root.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.canDo("previous")
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.runAction("previous")
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.playing ? "󰏤" : "󰐊"
            tooltipText: root.playing ? "Pause · Space" : "Play · Space"
            foreground: root.foreground
            horizontalPadding: Style.space(22)
            verticalPadding: Style.spacing.controlPaddingY
            iconSize: Style.space(28)
            selected: true
            accent: Color.accent
            radius: Style.cornerRadius
            bordered: false
            // The transport is where the keyboard cursor rests by default, so
            // it carries the cursor mark when nothing in the source list does.
            hasCursor: root.cursorIndex < 0
            enabled: root.canDo("playPause")
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.runAction("playPause")
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒭"
            tooltipText: "Next"
            foreground: root.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.canDo("next")
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.runAction("next")
          }

          Button {
            visible: root.canSeek
            anchors.verticalCenter: parent.verticalCenter
            text: "+10"
            tooltipText: "Forward 10 seconds"
            foreground: root.dim
            onClicked: root.seekBy(10)
          }

          Button {
            visible: root.hasLoop
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.loopIcon
            tooltipText: root.loopTooltip
            selected: root.loopActive
            foreground: root.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.cycleLoop()
          }
        }

        // ---- Volume. Right-click mutes, the same secondary action the audio
        //      panel's sliders carry, so the gesture transfers.
        Item {
          width: parent.width
          visible: root.hasVolume
          implicitHeight: visible ? volumeSlider.implicitHeight : 0

          Text {
            id: volumeIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(22)
            text: root.hasPlayer ? MediaModel.volumeIcon(root.volumeValue, root.volumeMuted) : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleMute()

              PanelToolTip {
                visible: parent.containsMouse
                text: root.volumeMuted ? "Unmute" : "Mute"
                fontFamily: root.fontFamily
              }
            }
          }

          Text {
            id: volumePercent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(42)
            horizontalAlignment: Text.AlignRight
            text: root.volumeMuted ? "Mute" : Math.round(root.volumeValue * 100) + "%"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSlider {
            id: volumeSlider
            anchors.left: volumeIcon.right
            anchors.leftMargin: Style.space(8)
            anchors.right: volumePercent.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            bar: root.bar
            minimum: 0
            maximum: 1
            step: 0.05
            value: root.volumeValue
            onMoved: function(value) { root.setVolume(value) }
            onReleased: function(value) { root.setVolume(value) }
            onRightClicked: root.toggleMute()
          }
        }

      }
    }

    // ---- Sources. Only worth a section once there is a choice to make.
    PanelSectionHeader {
      visible: root.sourcePlayers.length > 1
      width: parent.width
      text: "AUDIO SOURCES · " + root.sourcePlayers.length
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Column {
      id: sourceList
      visible: root.sourcePlayers.length > 1
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: root.sourcePlayers

        Column {
          id: sourceEntry
          required property var modelData
          required property int index

          readonly property var player: modelData
          readonly property bool selected: root.activePlayer === player
          readonly property bool cursored: root.cursorIndex === index
          onCursoredChanged: if (cursored) Qt.callLater(function() {
            if (root.hub) root.hub.ensureActiveRectVisible(sourceList.y + sourceEntry.y, sourceRow.height)
          })
          readonly property string sourceTitle: root.labelFor(player)
          readonly property string sourceDetail: [player ? player.identity : "", player ? player.trackArtist : ""].filter(function(s) { return !!s }).join(" · ")
          readonly property var streams: root.streamsFor(player)
          readonly property string entryKey: root.playerKey(player)
          readonly property bool expandable: streams.length > 1
          readonly property bool expanded: expandable && root.isExpanded(entryKey)

          width: sourceList.width
          spacing: Style.space(2)

          BorderSurface {
            id: sourceRow
            width: parent.width
            height: sourceInner.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: sourceEntry.selected
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10)
              : (sourceEntry.cursored || sourceMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : "transparent")
            borderSpec: sourceEntry.selected || sourceEntry.cursored
              ? Border.controlSpec("normal", root.foreground, Color.accent)
              : Border.none()

            Row {
              id: sourceInner
              // Above the row-wide MouseArea below, which is declared after
              // this and would otherwise sit on top of it and swallow every
              // click meant for the chevron.
              z: 1
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                text: sourceEntry.player && sourceEntry.player.isPlaying ? "󰏤" : "󰐊"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26) - (sourceEntry.expandable ? Style.space(26) : 0)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  text: sourceEntry.sourceTitle
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceEntry.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  text: sourceEntry.sourceDetail
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }

              // Only a source with more than one stream has anything to
              // unfold, so the chevron is the count made visible.
              Text {
                visible: sourceEntry.expandable
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                text: sourceEntry.expanded ? "󰅀" : "󰅂"
                color: chevronMouse.containsMouse ? root.foreground : root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.body

                MouseArea {
                  id: chevronMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleExpanded(sourceEntry.entryKey)

                  PanelToolTip {
                    visible: chevronMouse.containsMouse
                    text: sourceEntry.expanded ? "Hide the individual streams" : sourceEntry.streams.length + " streams making sound"
                    fontFamily: root.fontFamily
                  }
                }
              }
            }

            MouseArea {
              id: sourceMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectSource(sourceEntry.player)
              onEntered: root.cursorIndex = sourceEntry.index
              onExited: if (root.cursorIndex === sourceEntry.index) root.cursorIndex = -1
            }
          }

          // ---- The app's own level: reads the loudest of its streams and
          //      moves all of them together.
          //
          // Hidden on the selected source, because the slider under the
          // timeline is already this exact control over these exact streams.
          // Two of them side by side were not two controls, they were one
          // control drawn twice. Unfolding still shows the per-stream rows,
          // which are the only thing up there cannot reach.
          Item {
            width: parent.width
            visible: sourceEntry.streams.length > 0 && !sourceEntry.selected
            implicitHeight: visible ? appVolumeSlider.implicitHeight : 0

            Text {
              id: appVolumeIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.space(26)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              text: MediaModel.volumeIcon(root.appVolume(sourceEntry.streams), root.appMuted(sourceEntry.streams))
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleAppMute(sourceEntry.streams)

                PanelToolTip {
                  visible: parent.containsMouse
                  text: root.appMuted(sourceEntry.streams) ? "Unmute this app" : "Mute this app"
                  fontFamily: root.fontFamily
                }
              }
            }

            PanelSlider {
              id: appVolumeSlider
              anchors.left: appVolumeIcon.right
              anchors.leftMargin: Style.space(6)
              anchors.right: streamCount.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              minimum: 0
              maximum: 1
              step: 0.05
              value: root.appVolume(sourceEntry.streams)
              onMoved: function(value) { root.setAppVolume(sourceEntry.streams, value) }
              onReleased: function(value) { root.setAppVolume(sourceEntry.streams, value) }
              onRightClicked: root.toggleAppMute(sourceEntry.streams)
            }

            Text {
              id: streamCount
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: sourceEntry.streams.length > 1
                ? sourceEntry.streams.length + " streams"
                : Math.round(root.appVolume(sourceEntry.streams) * 100) + "%"
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---- The streams themselves. Numbered by the order they started,
          //      because that is the only thing that distinguishes them —
          //      the browser labels every one of them "Playback".
          Column {
            width: parent.width
            visible: sourceEntry.expanded
            spacing: Style.space(2)
            topPadding: visible ? Style.space(2) : 0
            bottomPadding: visible ? Style.space(4) : 0

            Repeater {
              model: sourceEntry.expanded ? sourceEntry.streams : []

              Item {
                required property var modelData
                required property int index

                width: parent.width
                implicitHeight: streamSlider.implicitHeight

                Text {
                  id: streamLabel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(46)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  text: String(index + 1)
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: streamMute
                  anchors.left: streamLabel.right
                  anchors.leftMargin: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(20)
                  text: MediaModel.volumeIcon(
                    modelData.audio ? modelData.audio.volume : 0,
                    modelData.audio ? modelData.audio.muted : false)
                  color: (modelData.audio && modelData.audio.muted) ? root.faint : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleStreamMute(modelData)

                    PanelToolTip {
                      visible: parent.containsMouse
                      text: (modelData.audio && modelData.audio.muted) ? "Unmute" : "Mute this one to find out which it is"
                      fontFamily: root.fontFamily
                    }
                  }
                }

                PanelSlider {
                  id: streamSlider
                  anchors.left: streamMute.right
                  anchors.leftMargin: Style.space(6)
                  anchors.right: streamPercent.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  bar: root.bar
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: modelData.audio ? modelData.audio.volume : 0
                  onMoved: function(value) { root.setStreamVolume(modelData, value) }
                  onReleased: function(value) { root.setStreamVolume(modelData, value) }
                  onRightClicked: root.toggleStreamMute(modelData)
                }

                Text {
                  id: streamPercent
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: Math.round((modelData.audio ? modelData.audio.volume : 0) * 100) + "%"
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }
}
