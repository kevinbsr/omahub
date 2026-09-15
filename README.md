# Kevin Hub

A keyboard-first command center for Omarchy. One themed bar widget opens a
single panel for calendar, media, weather, screen time, phone controls, nearby
sharing and system monitoring.

The Hub follows the active Omarchy theme for color, typography, borders,
spacing and corner radius. It keeps the original shell's compact, practical
character while bringing related controls into one consistent surface.

## Highlights

- Calendar with date selection, copy actions, year progress and life progress.
- MPRIS and PipeWire media controls with per-source volume and window focus.
- Open-Meteo weather with rain, UV, sunrise, sunset and a three-day forecast.
- Screen-time history, comparison, weekly trend and app breakdown.
- KDE Connect phone actions and LocalSend-compatible nearby sharing.
- Sleep-aware CPU, memory, GPU and storage monitoring with a btop shortcut.
- Mouse and keyboard navigation across all seven pages.

## Requirements

- Omarchy Quattro with its Quickshell-based shell.
- A Nerd Font for interface glyphs.
- `curl`, `python3`, `wl-clipboard` and `btop`; these are present on a normal
  Omarchy installation or available from Arch repositories.

Screen Time, Phone and Nearby are optional integrations. Their tabs explain
what is missing and provide a setup action when the corresponding plugin is
installed.

## Install

```bash
omarchy plugin add https://github.com/kevinbsr/kevin-hub.git --enable --yes
```

Install the optional engines from their upstream projects:

```bash
omarchy plugin add https://github.com/ax1g/quickshell-screentime-plugin.git --enable --yes
omarchy plugin add https://github.com/jitendradara12/omaconnect.git --enable --yes
```

Nearby uses its own release installer because it includes a versioned helper:

```bash
curl -fsSL https://raw.githubusercontent.com/jfg96/omarchy-nearby/main/install.sh \
  -o /tmp/omarchy-nearby-install.sh
bash /tmp/omarchy-nearby-install.sh
```

Open each integration tab in the Hub and choose its setup action. The Hub
moves that plugin's settings into its own entry and disables the duplicate bar
widget or service while retaining existing history, pairing and identity data.

## Project layout

```text
BarWidget.qml      weather glyph + clock label + media glyph
Panel.qml          the popup: navigation sidebar, keyboard routing, settings writes
CalendarTab.qml    calendar page (was omarchy.clock's Panel.qml)
MediaTab.qml       media page    (redesigned; was kevin.media's PopupCard)
WeatherTab.qml     weather page  (was omarchy.weather's Panel.qml, view half)
WeatherSource.qml  weather data  (was omarchy.weather's Panel.qml, model half)
ScreenTimeTab.qml  screen time   (was agx.screen-time's Panel.qml)
KdeConnectTab.qml  phone         (omaconnect's Panel.qml state machine)
kdeconnect/        omaconnect's four sections, vendored — see VENDORED.md
NearbyTab.qml      nearby page   (oma.nearby's Panel.qml, view half)
NearbyModel.js     transfer formatting, from oma.nearby
SystemTab.qml      system page   (CPU, memory, GPU and storage)
scripts/sysmon_probe local, sleep-aware system data collector
Service.qml        shared panel/MPRIS service; owns `kevin.hub` and `kevin.hub.media`
ClockModel.js      date maths, from omarchy.clock
MediaModel.js      player ranking helpers, from omarchy.media
WeatherModel.js    wttr/open-meteo parsing, from omarchy.weather
ScreenTimeModel.js formatting and grouping, from agx.screen-time
```

The media page splits its controls in two on purpose. Transport — play,
pause, next, previous — goes through `Service.qml`, so a click there and a
media key are the same action against the same player ranking. Seeking,
shuffle and loop have no media key and no service route, so they are set on
the active MPRIS player directly.

Volume is the exception to the exception: it goes to **PipeWire**, not MPRIS.
Chromium advertises the MPRIS `Volume` property and silently discards writes
to it — measured, not assumed: setting 0.35 leaves it reading 1.0 with the
audio untouched. The stream volume always works, and using it means this
slider and the active source's row in the list are the same number rather
than two that disagree. MPRIS volume survives only as a fallback for a player
with no live stream to point at.

Every control on the page is drawn only where the player reports it works, so
nothing appears as dead decoration — a browser gets no shuffle or loop button,
where Spotify gets both.

Position is polled, not bound — MPRIS does not push it — and the poll runs
only while the page is the one on screen, which is what `tabShown`/`tabHidden`
buy. Nerd-font codepoints for its glyphs were confirmed by rendering them,
not from memory: `F049C`, plausibly "shuffle_disabled", is a printer.

Its sources list reaches past MPRIS into PipeWire. One player can own several
playback streams — Chromium opens one per tab that makes sound — so each
source row carries an app-level volume that moves all of its streams
together, and unfolds (chevron, or `e`) into one slider and mute per stream.

The selected source is the exception: its app-level slider is hidden, because
the one under the timeline is already that same control over those same
streams. Unfolding it still works — the per-stream rows are the part the
slider above cannot reach.

Those per-stream rows are numbered, not named, and that is a limit of the
browser rather than a shortcut here: every Chromium stream is called
`media.name = "Playback"`, with only `client.id` / `object.id` /
`object.serial` telling them apart. Nothing anywhere maps a stream to a tab.
They are ordered by `object.serial`, which only counts up, so the numbering
is the order they started in — and the mute button is how you find out which
is which.

The chevron carries `z: 1` on the row's content for a reason: the MouseArea
that selects the whole source is declared after it, and a later sibling sits
on top in QML, so without the lift it swallowed every click aimed at the
chevron. Hover told the story — the tooltip never appeared either.

`Service.qml` carries one deliberate divergence from the `omarchy.media` it
was cloned from: in `selectActivePlayer`, an explicit pick from the sources
list now outranks the heuristics instead of sitting behind them. Upstream put
it after "whoever holds a PipeWire playback stream", and Spotify keeps its
stream open while paused where a browser drops its own — so clicking a paused
browser source stored the preference and changed nothing on screen. Keep this
in mind on any resync.

`Service.qml` is the shared engine used by the Hub's media page and bar
controls. The shell keeps ownership of its built-in `media` IPC target, while
the Hub exposes its source-aware controls through `kevin.hub.media`; this
avoids an ambiguous handler when both services are loaded.

`HubIntegrations.qml` loads one installed engine for Screen Time, Phone and
Nearby inside the Hub service. Current Omarchy versions restrict
`serviceFor()` to the calling plugin, so the pages read the Hub's own engine
references instead of looking up other plugins' services.

The dependencies must remain installed: `agx.screen-time` 1.5.0,
`omaconnect` 1.4.0 and `oma.nearby` 1.1.2 were checked with this integration.
Their service files, supporting scripts and data formats remain upstream;
no external plugin source is patched. Updates to those engines should be
checked against the Hub's copied views before distribution.

`scripts/integration_service.py enable <id>` moves the selected integration's
preferences into `kevin.hub.integrations`, removes its standalone service/bar
entries, and marks its standalone plugin disabled. This gives the engine a
single owner, preserving the original tracking history, KDE Connect pairing
and Nearby identity. Re-enabling a standalone plugin makes the Hub relinquish
its engine; do not enable both copies when configuring the desktop manually.
The helper backs up shell.json, preserves unrelated entries and writes it
atomically. Repeated activation is idempotent.

The four Phone sections under `kdeconnect/` remain vendored; see
`kdeconnect/VENDORED.md`. `NearbyTab.qml` keeps the file chooser and clipboard
with the view, while the engine owns discovery and transfer state. Receiver
preferences are forwarded to the Hub's scoped settings API. Incoming requests
remain explicit user actions; no transfer is accepted or sent automatically.

`WeatherSource.qml` is split out of the page for the same kind of reason.
Pages load on first visit, but the bar glyph has to show a condition from
startup, so `Panel.qml` owns one `WeatherSource` and hands it to both the
page and (through the panel) the bar widget. **A module whose bar presence
outlives its page needs this split**; a module that only exists inside its
page does not.

## Visual refresh — 2026-09-15

Seven destinations remain in the sidebar; content starts immediately alongside
it, without a separate title bar. The close action sits below navigation.

- Media: larger artwork with a loading/error fallback, multiline track title,
  one player surface, timeline above transport, and a distinct audio-source list.
  Seek-capable players expose −10/+10 second buttons. Click the right-hand time
  or press `t` to switch remaining/total duration. The volume shows a percentage.
  Existing keyboard/media actions and PipeWire stream controls are preserved.
- Calendar: compact month/year header with navigation and a Today button;
  selectable dates, relative day counts and copy actions below the grid.
  Year/lifetime meters stay visible below the selected date.
- Weather: current temperature and location above three equal metric cells;
  forecast days use vertical icon/temperature columns. Location editing remains.
- Screen time: live focus, today/yesterday/average comparisons, selectable
  daily app breakdown, a permanent weekly trend and retained history.
- Phone and Nearby: connection summaries sit in matching inset surfaces. The
  vendored device components, pairing and transfer behavior remain unchanged.
- System: CPU, RAM, swap, integrated/discrete GPUs and storage in compact
  metric cards, with a direct action to open btop.

Keys 1–7 and Tab navigate pages. Escape exits an editor first or closes the
panel. All pages were inspected in the running shell.

## Volume routing — 2026-09-15

The Hub matches audio streams using the desktop entry, MPRIS D-Bus name and
visible player identity against PipeWire application IDs, process binaries and
labels. This also covers Spotifast: its `fastpotify` stream publishes a process
binary but leaves its application, node and media names empty. Previously it
fell back to MPRIS instead of controlling that stream through PipeWire.

Regression checks: `node --test tests/media-volume.test.cjs`. Live verification
exercised the volume slider's moved/released signals at 35% and 60%; the Hub and
`wpctl get-volume` agreed at both settings. The initial volume was restored.
No diagnostic IPC interface remains installed.

## Focus the player

Click the album cover, or press `o` on the media page, to dismiss the Hub and
focus the selected player's existing window. Matching uses application identity
and prefers a window whose title contains the current track. If no compositor
window matches, the player's MPRIS Raise action is used when supported. Cover
hover shows the destination; playback and volume are unchanged. For browsers,
this targets an existing matching window, not an arbitrary hidden tab.

## Adding a module

1. Write `<Name>Tab.qml`. It is a plain `Item` that lays itself out and
   reports an honest `implicitHeight`; `Panel.qml` gives it the popup, the
   scrolling and the chrome.
2. Add one line to `tabs` in `Panel.qml`:

```qml
{ id: "timers", label: "Timers", icon: "󰔛", source: "TimersTab.qml", minWidth: Style.space(420) }
```

That is the whole change. The strip, the digit shortcut, the lazy loading
and the persisted last-used tab all follow from the list.

### What a tab may declare

All optional — declare what you need and ignore the rest.

| Member | Purpose |
|---|---|
| `property var hub` | this panel: `setting()`, `persistSettings()`, `close()` |
| `property QtObject bar` | the bar host (`bar.shell`, `bar.run`, …) |
| `property color foreground` | theme foreground, injected |
| `property string fontFamily` | theme font, injected |
| `property bool keysBlocked` | true while an inline editor owns the keyboard |
| `function handleMove(dx, dy)` | arrow keys / hjkl |
| `function handleActivate()` | Enter / Space |
| `function handleTextKey(t)` | one printable key |
| `function refresh()` | panel opened, or `refresh` came over IPC |
| `function handleClose()` | Escape; return true to keep the panel open |
| `function tabShown()` | became the visible page of an open panel |
| `function tabHidden()` | stopped being it — tab switch or panel close |
| `function panelClosed()` | panel dismissed; drop transient state |

Settings are shared: every tab reads and writes the one `kevin.hub` entry in
`shell.json`, so prefix keys that could collide.

There is one bar widget per monitor and one shared `Panel.qml` in the singleton
service. The widget that opens it becomes its host, which gives the panel the
correct screen and anchor. The active tab stays in memory while the panel is
open and is written to `shell.json` only after close, avoiding a plugin reload
on every tab switch.

## Keys

| Key | Does |
|---|---|
| `Tab` / `Shift+Tab` | next / previous page, then off to the next bar panel |
| `1`…`9` | jump to a page |
| `Esc` | close |

Calendar: `←`/`→` select the previous/next day, `↑`/`↓` move one week,
`[`/`]` change month, `{`/`}` change year, `t` selects today, `w` changes
the week start. `c`/`Enter` copy dd/mm/yyyy; `i` copies yyyy-mm-dd.
Double-click life progress to edit it (Escape cancels). If no birth year is
configured, double-click year progress for initial setup.
Media: `←`/`→` seek ∓5s (skip tracks instead on a player that cannot seek),
`↑`/`↓` walk sources, `Enter` play/pause or pick the cursored source,
`p` play-pause, `n`/`b` next / back, `m` mute, `s` shuffle, `r` repeat,
`e` unfold the cursored source's individual streams.
Weather: `Enter` edits the location, then `↑`/`↓` walk the suggestions.
Screen: `←`/`→` selects days, `t` returns to today and `h` opens retained
history. The seven-day pattern remains visible.
Phone: arrows walk devices / actions / commands, `Enter` activates, `r`
refreshes, `p` pairs, `u` unpairs, then `y` / `c` confirm or cancel. Escape
backs out of a confirmation or a composer before it closes the panel.
Nearby: `↑`/`↓` walk the receiver toggle, the devices and the rescan row,
`Enter` activates. Escape backs out of a PIN prompt or a chosen target first.
System: `r` refreshes immediately; `b` or `Enter` opens btop.

`tabShown` / `tabHidden` exist for modules that cost something while looked
at. Nearby starts discovery and System starts its two-second sampling only
while their respective pages are visible. Both stop as soon as you switch tabs.

A page that does not claim `↑`/`↓` gets the panel's default for them, which
is to scroll itself — so a tall module needs no Flickable of its own.

## The bar

Three hit areas in one slot: `󰖐  Monday 01:39  󰏤`

| | Weather glyph | Clock label | Media glyph |
|---|---|---|---|
| left | the weather page | **the calendar** | play / pause |
| right | conditions as a notification | cycle the label format | the media page |
| middle | refetch the forecast | timezone picker | next track |
| scroll | — | — | previous / next |

Each of those page clicks is a toggle *onto* a page, never a resume of
wherever the panel was last left. The clock is about the date, so it opens
the calendar every time, whatever tab the panel closed on; a second click
with that page already up is what closes the panel, and clicking a different
glyph switches pages instead of closing.

The persisted last-used tab still governs `omarchy-shell kevin.hub toggle`
and a fresh session — it is only the bar's glyphs that override it, because
each one is a question with a specific answer.

Media keeps the bindings `kevin.media` had, with "the popup" now meaning the
media page. Its glyph collapses when no player is around and dims when one
is paused, so the bar is just a clock when there is nothing to press.

Both glyphs sit in fixed-width slots on purpose. This widget is the bar's
`centerAnchor`, so a sun becoming a thunderstorm — or a play triangle
becoming a pause bar — would otherwise drag the whole center row sideways.

## IPC

```bash
omarchy-shell kevin.hub toggle
omarchy-shell kevin.hub tab weather    # open straight onto a page
omarchy-shell kevin.hub tabToggle calendar  # what the clock glyph does
omarchy-shell kevin.hub cycleFormat    # same as right-clicking the label
omarchy-shell kevin.hub refreshWeather
omarchy-shell kevin.hub.media playPause # Hub player ranking and source choice
```

## Gotcha

Saving a file here usually hot-reloads, but the watcher does go stale. If an
edit does not seem to apply — settings arriving empty is the tell — run
`omarchy restart shell` before debugging the code.

## Media controls and integration setup

Media keeps artwork, metadata, transport, timeline and volume visible.
Shuffle, repeat and ten-second seeking are always shown when supported by the
player. Audio sources appear whenever more than one player is available.
Arrow navigation scrolls the selected source into view; `E` unfolds its streams.

On the cover, left-click focuses the player, scroll changes its volume by 5%
per wheel notch (clamped to 0–100%), and right-click toggles mute. Muting keeps
the previous volume; scrolling does not silently unmute it. The slider and
cover tooltip show the current volume.

Pages share a 480-unit preferred viewport, constrained to the monitor height;
longer content scrolls without resizing the panel when switching tabs.

Unavailable integrations offer a setup button backed by
`scripts/integration_service.py`. Activation requires the corresponding plugin
to be installed and moves its service into the Hub as described above. Nearby
also offers **Update Nearby** when its installed helper no longer satisfies
the plugin's version requirement; the upstream updater verifies the release
checksum before replacing the binary.

## Navigation and shortcut help

Click **?** beside the close button, or press `?`, for the current page's
keyboard shortcuts and common navigation keys. `Esc` returns to the page;
a second `Esc` follows the page's normal close behavior. Selecting a page
also leaves help. Help is disabled while an inline editor owns the keyboard,
so typing does not open it accidentally. Shortcuts in help never activate
hidden media, phone or sharing controls.

Overflowing pages now show draggable scrollbars with theme colors. The popup
width includes its own padding, borders and scrollbar gutter, so the full
calendar fits at the preferred size. On narrow displays the popup remains
within the monitor and horizontal scrolling keeps wider content reachable.

## Volume shortcuts

Audio output selection stays in Omarchy's native audio menu.

`+` (or `=`) and `−` adjust the active player's volume by 5 percentage points,
clamped to 0–100%. `M` toggles mute. Keyboard and cover scrolling share the same
volume handler; neither silently unmutes an already muted PipeWire stream.

Validation: `qmllint -I /usr/share/omarchy/shell *.qml`,
`node --test tests/media-volume.test.cjs`, and
`python3 -B tests/test_integration_service.py`.

## Weather refinements

The Weather page shows a clickable city heading, current temperature and
condition icon, feels-like temperature, wind and humidity. The next three days
show the day, condition icon and low/high temperatures in three side-by-side cards.
Temperature labels follow the selected unit. The footer reports the time of the last
successful update or a loading/error state.

Click the refresh button or press `R` for a new request. `U`, or the unit
button, switches between Celsius and Fahrenheit and saves the preference in
the Hub entry. Opening the page reuses a recent request instead of restarting
the network calls on every visit. The existing shared weather source and
normal refresh interval remain in use.

`Enter` opens a full-width city search. Results show the region and country;
arrows select a result and `Enter` saves it. Cancel (or `Esc`) leaves the saved
city alone; **Use automatic location** explicitly restores IP-based detection.
Typing clears old suggestions, superseded responses are discarded, and empty
results or failed searches get distinct feedback. Free-text saves require a
resolved search result, preventing a city name from being paired with the old
coordinates. A city change invalidates the previous reports so they are never
shown as the new city's weather. Fetch retries remain bounded; a saved city
with unavailable weather no longer leaves the editor spinning indefinitely.

## Rain, UV and solar times

The blue temperature range bars have been removed. Today shows peak
precipitation probability and total rain, plus daily maximum UV, sunrise and
sunset. Each of the next three days shows only the day, condition icon and
low/high temperatures; the extra daily detail has been removed from those rows.

The existing Open-Meteo request now includes
`precipitation_probability_max`, `rain_sum`, `showers_sum`, `uv_index_max`,
`sunrise` and `sunset`; no additional weather request is needed. Rain totals
add rain and showers and exclude snowfall. The precipitation probability
is the daily maximum probability, not the fraction of the day with rain.
UV is the forecast daily maximum rather than the current reading.
[Open-Meteo daily variable definitions](https://open-meteo.com/en/docs#daily-parameter-definition).

Solar times retain the selected city's local time returned by `timezone=auto`.
The city date, including its UTC offset, selects today's values and the next
three forecast dates even when the desktop is in a different timezone.
Unavailable, incomplete or invalid values render as `—`; a measured zero
remains zero. Days without a sunrise or sunset also show `—`.

Run the normalization/date tests with `node --test tests/weather-daily.test.cjs`.

Weather metric cards and forecast cards share one component: identical height,
corner radius, padding, label/value spacing and left alignment. Forecast icons
sit on the right of the value row. The current-condition surface follows the
same column guides, with a larger temperature readout.

## Calendar selection — 2026-09-15

The selected date survives page switches and reopening the panel. Today has
a subtle outline; the selected day uses the theme accent. Clicking an adjacent
month's day follows it into that month. Month/year navigation clamps the day
to the destination month's length, including leap years. Relative day counts
use calendar dates so daylight-saving transitions do not change the count.

Copy actions use `wl-copy` and show success or failure feedback. Progress
stays visible below the selected date; existing birth year and life expectancy
settings are preserved. Compact spacing keeps the calendar and progress meters
in view together at the preferred panel size.

Validation: `node --test tests/calendar-selection.test.cjs` covers month ends,
leap years, year boundaries, DST and adjacent-month cells. Live checks cover
keyboard selection, page-switch persistence, both clipboard formats and the
Progress editor's cancellation.

## Integration repairs — 2026-09-15

Screen Time reads its live history and activity state. Phone loads paired devices, battery and
actions. Enter on an already paired device selects its actions; unpairing still
requires its explicit control or U and confirmation. Device changes discard
stale drafts, and missing devices/capabilities no longer break hidden widgets.

Nearby's helper was updated from 1.0.7 to the matching 1.1.2 release using the
upstream updater and SHA256 verification. File/clipboard selection keeps the
chosen recipient and cancels dispatch if that target is no longer selected.
Received-text copying snapshots its content and ignores duplicate clicks.

Validation: configuration migration tests, all seven pages inspected live,
Screen patterns, paired-device keyboard navigation,
empty-device rendering, and Nearby receiver OFF/ON persistence. No messages,
files, pairing changes or remote commands were sent during validation; a real
transfer still requires a peer available for that test.

## System monitor — 2026-09-15

The System page replaces the separate `kevin.sysmon` bar entry. It reports CPU
load and temperature, RAM, swap, integrated and discrete GPU state, VRAM and
storage. The local `scripts/sysmon_probe` preserves the original runtime-PM
rule: it calls NVIDIA tooling only when the discrete GPU is already active, so
monitoring does not wake a suspended GPU.

Sampling runs every two seconds while System is visible and stops on page
switch or panel close. A failed reading keeps the last valid snapshot and
offers an explicit retry. `R` refreshes; `B` or Enter opens btop.

## Screen Time daily view — 2026-09-15

Patterns remain visible and the page compares today, yesterday and the average
of retained completed days from the previous week. The active application has
a session timer maintained by the Hub, without changing the upstream tracking
history. Daily totals continue to mean focused-window time; lock and idle time
are excluded.

The arrows and weekly bars select a day and redraw the app ring from that day's
data. History expands only on request and lists every retained day with
activity; choosing one returns to the compact daily view. Meaningful distance
from the seven-day average and the busiest day remain visible at a glance.

Validation covers date boundaries, retained-history ordering, average and
comparison calculations, application labels, keyboard day selection, real
history rendering and the expanded history layout.
