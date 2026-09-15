Vendored from omaconnect, with the local compatibility fixes listed below.

    source:  https://github.com/jitendradara12/omaconnect
    path:    components/
    version: v1.1.0-15-g42dfa8b (42dfa8b)
    copied:  2026-08-18

These four sections are upstream's, copied verbatim so this plugin does not
bind to another plugin's internal `panel.*` contract across updates. The
matching state machine — the `panel` object they read — is the top half of
KdeConnectTab.qml, ported from upstream's Panel.qml at the same revision.

They still call `panel.service`, which resolves to the live
engine hosted by `HubIntegrations.qml`. That service is a published wrapper of aliases
(its own BarWidget uses it), and its changes have been additive; the two
functions this revision needs are `clearActionState()` and
`installDependencies()`.

To resync:

    cd ~/.config/omarchy/plugins/omaconnect && git log --oneline HEAD..origin/main
    # if components/ or Panel.qml moved, recopy the four files and
    # re-port the state machine at the top of KdeConnectTab.qml

Local compatibility fixes (2026-09-15): guard missing selected devices and
capabilities in DeviceSection.qml and ComposerSection.qml. Preserve these
guards when resyncing upstream components.
