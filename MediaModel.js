function isProxyPlayer(player) {
  var dbusName = String(player && player.dbusName || "").toLowerCase()
  var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function hasMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
}

function hasTrackMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.trackAlbum || player.trackArtUrl))
}

function playerCanControl(player) {
  return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause || player.canGoNext || player.canGoPrevious))
}

function canHandleAction(player, action) {
  if (!player) return false
  if (action === "next") return !!player.canGoNext
  if (action === "previous") return !!player.canGoPrevious
  if (action === "play") return !!(player.canPlay || player.canTogglePlaying)
  if (action === "pause") return !!(player.canPause || player.canTogglePlaying)
  if (action === "playPause") return !!(player.canTogglePlaying || player.canPlay || player.canPause)
  return false
}

function canCycleSource(player) {
  return !!(player && hasMetadata(player) && (player.isPlaying || player.canPlay))
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function streamLabelKey(label) {
  var key = String(label || "").toLowerCase()
  key = key.replace(/^pipewire alsa \[/, "")
  key = key.replace(/\]$/, "")
  key = key.replace(/^alsa playback \[/, "")
  key = key.replace(/[^a-z0-9]+/g, "")
  return key
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"]
    || node.description
    || p["media.name"]
    || p["node.name"]
    || node.name
}

function playerAppLabel(player) {
  if (!player) return ""
  var dbus = String(player.dbusName || "")
  dbus = dbus.replace(/^org\.mpris\.MediaPlayer2\./, "")
  dbus = dbus.replace(/\.instance[0-9]+$/, "")
  return player.desktopEntry || player.identity || dbus
}

// Match every stable application identity rather than one display label.
// Some clients (Spotifast/fastpotify) leave all stream names empty but do
// publish application.process.binary; browsers may use different labels
// for their desktop entry, MPRIS identity and audio process.
function identityKeys(values) {
  var keys = []
  for (var i = 0; i < values.length; i++) {
    var label = String(values[i] || "").replace(/^org\.mpris\.MediaPlayer2\./i, "")
      .replace(/\.instance[0-9]+$/i, "").replace(/\.desktop$/i, "")
    var key = streamLabelKey(label)
    if (key && ["audio", "playback", "stream", "unknown"].indexOf(key) === -1 && keys.indexOf(key) === -1)
      keys.push(key)
  }
  return keys
}

function streamMatchesPlayer(player, node) {
  if (!player || !node || !node.ready) return false
  var props = nodeProps(node)
  var playerKeys = identityKeys([player.desktopEntry, player.dbusName, player.identity])
  var streamKeys = identityKeys([props["application.id"], props["application.process.binary"],
    props["application.name"], rawStreamLabel(node)])
  for (var p = 0; p < playerKeys.length; p++) {
    for (var n = 0; n < streamKeys.length; n++) {
      var a = playerKeys[p], b = streamKeys[n]
      if (a === b) return true
      // Preserve decorated application-name matching without letting a
      // short identifier like "mpv" claim another application's stream.
      if (Math.min(a.length, b.length) >= 4 && (a.indexOf(b) !== -1 || b.indexOf(a) !== -1)) return true
    }
  }
  return false
}

function playerHasPlaybackStream(player, playbackStreams) {
  return streamsForPlayer(player, playbackStreams).length > 0
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function trackSignature(player) {
  if (!player) return ""
  return [
    player.trackTitle || "",
    player.trackArtist || "",
    player.trackAlbum || "",
    player.trackArtUrl || ""
  ].join("\u001f")
}

function trackChanged(previousSignature, player) {
  return trackSignature(player) !== String(previousSignature || "")
}

function labelFor(player) {
  if (!player) return ""
  return player.trackTitle || player.identity || player.desktopEntry || ""
}

function osdMessage(player, fallback) {
  if (!player) return fallback
  var label = labelFor(player)
  if (label && player.trackArtist) return label + " - " + player.trackArtist
  return label || fallback
}

// Clock-style duration. MPRIS reports seconds as a double; an hour-long
// podcast needs the hour field and a three-minute song must not carry an
// empty one, so the shape follows the value.
function fmtTime(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var s = total % 60
  var m = Math.floor(total / 60) % 60
  var h = Math.floor(total / 3600)
  var mm = (h > 0 && m < 10) ? "0" + m : String(m)
  var ss = s < 10 ? "0" + s : String(s)
  return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
}

// Speaker glyph for a 0..1 level, so the icon carries the level as well as
// the slider does.
function volumeIcon(volume, muted) {
  if (muted || volume <= 0.001) return "󰝟"
  if (volume < 0.34) return "󰕿"
  if (volume < 0.67) return "󰖀"
  return "󰕾"
}

// Every playback stream a player owns, oldest first.
//
// The browser is the reason this returns a list rather than the boolean
// playerHasPlaybackStream gives: Chromium opens one stream per tab that makes
// sound, so one MPRIS player can sit on top of four independent volumes.
// They are matched by application identifiers, including the process binary —
// nothing in a stream says which tab it belongs to.
function streamsForPlayer(player, playbackStreams) {
  var out = []
  var streams = Array.isArray(playbackStreams) ? playbackStreams : []
  for (var i = 0; i < streams.length; i++) {
    if (streamMatchesPlayer(player, streams[i])) out.push(streams[i])
  }

  // object.serial only ever counts up, so it is the order the streams
  // started in — the one stable thing to number them by.
  out.sort(function(a, b) { return streamSerial(a) - streamSerial(b) })
  return out
}

function streamSerial(node) {
  return Number(nodeProps(node)["object.serial"]) || 0
}

// Prefer the player's window that shows this track, then its active window.
// A title match alone is insufficient: another app can show the same text.
function windowForPlayer(player, windows) {
  if (!player) return null
  var best = null, bestScore = -1
  var track = String(player.trackTitle || "").toLowerCase()
  var list = windows || []
  for (var i = 0; i < list.length; i++) {
    var window = list[i]
    if (!window || !streamMatchesPlayer(player, {ready:true, properties:{"application.id":window.appId}})) continue
    var title = String(window.title || "").toLowerCase()
    var score = (track && title.indexOf(track) !== -1 ? 100 : 0) + (window.activated ? 10 : 0)
    if (score > bestScore) { best = window; bestScore = score }
  }
  return best
}

if (typeof module !== "undefined") {
  module.exports = {
    isProxyPlayer: isProxyPlayer,
    hasMetadata: hasMetadata,
    hasTrackMetadata: hasTrackMetadata,
    playerCanControl: playerCanControl,
    canHandleAction: canHandleAction,
    canCycleSource: canCycleSource,
    nodeProps: nodeProps,
    isPlaybackStream: isPlaybackStream,
    streamLabelKey: streamLabelKey,
    rawStreamLabel: rawStreamLabel,
    playerAppLabel: playerAppLabel,
    playerHasPlaybackStream: playerHasPlaybackStream,
    playerKey: playerKey,
    trackSignature: trackSignature,
    trackChanged: trackChanged,
    labelFor: labelFor,
    osdMessage: osdMessage,
    fmtTime: fmtTime,
    volumeIcon: volumeIcon,
    streamsForPlayer: streamsForPlayer,
    streamMatchesPlayer: streamMatchesPlayer,
    windowForPlayer: windowForPlayer,
    streamSerial: streamSerial
  }
}
