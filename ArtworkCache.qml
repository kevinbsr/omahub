import QtQuick
import Quickshell
import Quickshell.Io

// A bounded door between MPRIS artwork and the shell's image loader.
//
// `trackArtUrl` is whatever the player put on the bus: Spotify and browsers
// publish https URLs, most local players publish file:// paths into /tmp.
// Handing that string straight to an Image means any process that can own an
// MPRIS name -- which is any process the user runs -- can make the shell fetch
// an arbitrary URL over an arbitrary scheme, of arbitrary size, and hold the
// decoded result in memory for as long as the track is selected.
//
// So the string is not trusted, and what the Image gets is always a local file:
//
//   file://   used as is. It is already on this machine, and the Image's
//             sourceSize bounds what is decoded out of it.
//   https://  fetched by curl into ~/.cache/omahub/artwork with a byte
//             ceiling, a deadline, an https-only protocol set (so a redirect
//             cannot walk down to http or file), and a local content sniff --
//             `file --mime-type` on the bytes received, not the server's
//             say-so. The cache keeps the newest few files and nothing else.
//   anything  dropped, and the page shows its placeholder glyph. http, data:,
//   else      ftp and whatever comes next are all in here on purpose.
//
// Caching by URL hash also means a track returning to the top of the queue
// does not re-fetch, which is the pleasant half of the same decision.
Item {
  id: root

  // The untrusted input.
  property string source: ""

  // Largest artwork accepted, in bytes. Album art an order of magnitude past
  // this is not album art.
  readonly property int maxBytes: 4 * 1024 * 1024
  readonly property int keepFiles: 24

  // What the Image should load: a local file, or "" for none yet.
  readonly property url ready: resolved !== "" ? Qt.resolvedUrl(resolved) : ""
  property string resolved: ""
  property bool fetching: false

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/omahub/artwork"

  onSourceChanged: root.evaluate()
  Component.onCompleted: root.evaluate()

  function evaluate() {
    var raw = String(root.source || "").trim()
    if (raw === "") {
      root.resolved = ""
      return
    }
    if (raw.indexOf("file://") === 0) {
      root.resolved = raw
      return
    }
    if (raw.indexOf("https://") !== 0) {
      // Not a scheme this will fetch; say so once, quietly, and show nothing.
      root.resolved = ""
      return
    }
    var target = root.cacheDir + "/" + Qt.md5(raw)
    root.resolved = ""
    fetchProc.wanted = raw
    fetchProc.target = target
    fetchProc.command = ["bash", "-c", root.script,
      "omahub-artwork", raw, target, root.cacheDir,
      String(root.maxBytes), String(root.keepFiles)]
    root.fetching = true
    fetchProc.running = true
  }

  // $1 url, $2 target file, $3 cache dir, $4 max bytes, $5 files to keep.
  // The URL is a positional argument and is never interpolated into this
  // text, so a player publishing `$(...)` as its artwork URL publishes a
  // string. head -c takes max+1 so a file that lands exactly on the ceiling
  // is rejected rather than quietly truncated into a broken image.
  readonly property string script: [
    'set -u -o pipefail',
    'dir=$3; out=$2; max=$4; keep=$5',
    'if [ -s "$out" ]; then exit 0; fi',
    'mkdir -p "$dir" || exit 1',
    'tmp=$(mktemp "$dir/.part-XXXXXX") || exit 1',
    'trap \'rm -f "$tmp"\' EXIT',
    'curl -fsSL --proto "=https" --max-time 8 --max-filesize "$max" -- "$1" | head -c $((max + 1)) > "$tmp" || exit 2',
    '[ -s "$tmp" ] || exit 3',
    '[ "$(stat -c %s "$tmp")" -le "$max" ] || exit 4',
    'case "$(file -b --mime-type "$tmp")" in image/*) ;; *) exit 5 ;; esac',
    'mv -f "$tmp" "$out" || exit 6',
    'trap - EXIT',
    // Bounded cache: newest `keep` files stay, the rest go. Nothing here is
    // precious -- a dropped file is one re-fetch.
    'ls -1t "$dir" 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r old; do rm -f "$dir/$old"; done',
    'exit 0'
  ].join("\n")

  Process {
    id: fetchProc
    property string wanted: ""
    property string target: ""
    onExited: function(code) {
      root.fetching = false
      // The track may have changed while this was in flight; a late answer
      // must not overwrite the current one.
      if (fetchProc.wanted !== String(root.source || "").trim()) return
      root.resolved = code === 0 ? "file://" + fetchProc.target : ""
    }
  }
}
