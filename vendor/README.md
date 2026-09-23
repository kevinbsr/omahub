# Vendored engines

Upstream engines the Hub runs in its own process, each pinned to an exact commit
in `vendor.json`. **Nothing here is edited by hand.** Every local change is a
patch in `patches/<engine>/`, applied on top of that commit, so what the Hub
ships is always `upstream@commit + patches` and nothing else.

That rule is enforced rather than trusted: `tools/vendor-sync verify` rebuilds
each tree from upstream and fails if a single checked-in byte differs. It runs
on every push.

## Commands

```bash
tools/vendor-sync status            # what has upstream added since the pin?
tools/vendor-sync update <engine>   # repin to upstream HEAD, reapply the patches
tools/vendor-sync verify            # is the checked-in tree still derivable?
```

`update` refuses to leave a mess: if a patch no longer applies it stops and names
it, so the pin never moves past a change that silently dropped a local fix.
Rework the patch against the new upstream, then run `update` again.

A daily job (`.github/workflows/vendor-watch.yml`) runs `status` and files one
issue listing exactly which upstream commits are missing — the watching is not
someone's job to remember.

## Why a patch and not a fork

Upstream keeps fixing its own bugs, and a fork stops receiving that the day it is
made. A pin plus a small patch keeps both: upstream's work arrives with every
`update`, and the local change is one reviewable file that either still applies
or fails loudly. Each patch's header says what it does, why it exists, and when
it can be deleted — usually "once it lands upstream".

## Engines

| Engine | Upstream | License | Local patches |
|---|---|---|---|
| `screentime` | [ax1g/quickshell-screentime-plugin](https://github.com/ax1g/quickshell-screentime-plugin) | MIT | none |
| `omaconnect` | [jitendradara12/omaconnect](https://github.com/jitendradara12/omaconnect) | MIT | none |
| `android-mirror` | [ayandexyz/omarchy-android-mirror](https://github.com/ayandexyz/omarchy-android-mirror) | MIT | 1 — declare the mirror backend as a service entry point |

Only the engine is vendored, not the whole plugin: `include` in `vendor.json`
lists the exact files, which is the service and the scripts and data it reads.
Each upstream's bar widget and panel stay out — the Hub has its own views for
those, and pulling them in would vendor a second copy of the UI it replaced.

If the matching standalone plugin is installed and declares a service entry
point, `HubIntegrations.qml` loads *that* instead of the copy here. The vendored
tree is the floor, not a lock.

Licenses and attribution stay with the vendored files (each tree keeps its own
`LICENSE`), and `THIRD_PARTY_NOTICES.md` at the repo root lists them.
