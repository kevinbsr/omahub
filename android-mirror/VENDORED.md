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

Not vendored: pairing (connect by address, Wi-Fi pairing code), settings, and
tool installation. Those stay behind the "Open full panel" link, which opens
upstream's own Panel.qml through the shell's normal cross-plugin summon --
publicly permitted for a `bar-widget`-kind plugin, not a private API. Rare,
multi-step flows belong in the panel that was designed for them rather than
reimplemented here.

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
Panel.qml. `kevinbsr.omahub/scripts/integration_service.py`'s `ALLOWED` set gained
the plugin's id, and its `MANIFEST_PATCHES` table knows to add `"service"` to
`kinds` and `"entryPoints.service": "MirrorBackend.qml"` to android-mirror's
OWN `manifest.json` the first time it is enabled (`patch_manifest_for_service`,
idempotent, only touches that one file, only for plugin ids listed in the
table) -- that is what lets the Hub's "Enable" button host it the same way it
hosts the other three. `omarchy plugin update` on android-mirror overwrites
that patch; enabling it again through the Hub reapplies it. A PR proposing
the manifest addition upstream would remove the need for this table entry
entirely -- purely additive, no behavior change for anyone running the
plugin standalone. No such PR has been opened yet.

## To resync

    cd ~/.config/omarchy/plugins/io.github.ayan-de.android-mirror && git log --oneline HEAD..origin/main
    # if MirrorBackend.qml's device object shape, or the four functions this
    # relies on, changed -- reread Model.js and Panel.qml's device Repeater
    # and update AndroidMirrorModel.js / AndroidMirrorSection.qml to match
