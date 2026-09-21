// Vendored from omarchy-android-mirror's Model.js, verbatim -- see VENDORED.md.
// Presentation only: what a device row says, not how the device list is built.

function deviceTitle(d) {
  if (!d) return ""
  if (d.model !== "") return d.model
  return d.serial
}

function deviceSubtitle(d) {
  if (!d) return ""
  var bits = [d.transport === "wifi" ? "Wi-Fi" : "USB", d.serial]
  if (!d.ready) bits.push(stateHint(d.state))
  return bits.join(" · ")
}

function stateHint(state) {
  switch (state) {
    case "unauthorized": return "tap Allow on the phone"
    case "offline": return "offline — replug or reconnect"
    case "no permissions": return "udev: no USB permission"
    case "authorizing": return "authorizing…"
    default: return state
  }
}
