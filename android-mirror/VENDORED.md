Vendored from omarchy-android-mirror, with local additions listed below.

    source:  https://github.com/ayandexyz/omarchy-android-mirror
    path:    Model.js (three functions), device-row layout from Panel.qml
    version: 6330632

`AndroidMirrorModel.js` copies `deviceTitle`, `deviceSubtitle` and
`stateHint` from upstream's `Model.js` verbatim -- presentation-only, no
protocol logic. `AndroidMirrorSection.qml` is a compact rewrite of the device
`Repeater` block in upstream's `Panel.qml` (same fields, same actions: enable
Wi-Fi, disconnect, mirror/stop), trimmed for the Hub's narrower tab instead of
a standalone panel, and without the keyboard cursor/selection upstream's
Panel.qml drives for its own bar-widget shortcuts.

Not vendored: pairing (connect by address, Wi-Fi pairing code) and settings.
Those stay behind the "Open full panel" link, which opens upstream's own
Panel.qml through the shell's normal cross-plugin summon -- publicly permitted
for a `bar-widget`-kind plugin, not a private API. Rare, multi-step flows
belong in the panel that was designed for them rather than reimplemented here.

That link is only shown when the standalone plugin is actually installed, which
`HubIntegrations.qml` reports as `mirrorPluginPresent` (the manifest file
exists) -- a different question from `installed` (the manifest declares a
service). Since the Hub carries its own engine under `vendor/android-mirror`,
the common case is now that there is no standalone plugin and no full panel to
open. Tool installation moved into this section for exactly that reason: without
adb and scrcpy nothing here works at all, so a dead-end message was not an
option. The Install button calls upstream's own `installTools()`, the same
function the panel's button calls; it opens a floating terminal running
`omarchy pkg add scrcpy android-tools android-udev`. Pairing did not move: it is
a two-field form for a case a USB cable already solves, and the Wi-Fi button on
a plugged-in phone is the path most people take.

Both files bind to `MirrorBackend`'s state directly (`devices`, `loading`,
`toolsMissing`, `actionBusy`, `mirroring`, and the `enableWifi` / `disconnect`
/ `mirror` / `stopMirror` functions) -- the same engine upstream's own Panel.qml
runs, loaded once by `HubIntegrations.qml`. That surface is upstream's
internal contract, not a manifest-declared one; a MirrorBackend.qml refactor
could rename or restructure it without upstream considering that a breaking
change for their own plugin. `HubIntegrations.qml`'s failure detection
(`mirrorFailed`) is the safety net for that: a rename that breaks the *load*
notifies; a change to `MirrorBackend`'s properties or functions that leaves it
loading fine would show up as this section going quietly wrong instead, same
as an upstream `Panel.qml` change would for anyone running that panel.

## Manifest patch

Upstream's manifest declares only `"kinds": ["bar-widget"]`, with no service
entry point -- MirrorBackend.qml was never meant to be loaded by anything but
Panel.qml. The Hub used to add that entry to android-mirror's OWN
`manifest.json` the first time the integration was enabled. That is gone: it
wrote into someone else's installed plugin and their next `omarchy plugin
update` undid it, so the patch had to be reapplied forever.

The one-line change now lives as a patch on the vendored copy instead --
`../vendor/patches/android-mirror/0001-manifest-declare-service-entrypoint.patch`
-- applied on top of the pinned upstream commit by `tools/vendor-sync`, touching
only files this repo owns. An installed standalone android-mirror is left
exactly as upstream shipped it; because it declares no service, the Hub reads it
as not hostable and runs the vendored engine, while the standalone plugin keeps
working its own way.

A PR proposing the manifest addition upstream would let the patch be deleted --
purely additive, no behavior change for anyone running the plugin standalone.
None has been opened yet; the patch header says the same.

## To resync

    tools/vendor-sync status android-mirror   # what has upstream added since the pin?
    tools/vendor-sync update android-mirror   # repin, reapply the patch
    tools/vendor-sync verify                  # tree still == upstream@pin + patch?

`update` refuses to repin if the patch stops applying, so the manifest change
can never be dropped silently. After a repin, the question for the two files in
*this* directory is unchanged: if `MirrorBackend.qml`'s device object shape or
the four functions they rely on changed, reread `Model.js` and `Panel.qml`'s
device `Repeater` and update `AndroidMirrorModel.js` / `AndroidMirrorSection.qml`
to match.
