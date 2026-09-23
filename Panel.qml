import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

// The hub's panel: a tab strip over one page at a time.
//
// The panel itself knows nothing about calendars or media. It owns the
// chrome every module shares — the popup, the tab strip, keyboard routing,
// and writing settings back to shell.json — and each module is a QML file
// listed in `tabs` below. Adding a module is a file plus a line.
//
// ---- Tab contract -------------------------------------------------------
// An entry in `tabs` is:
//   { id, label, icon, source, minWidth }
// `id` is what selectTab() and the IPC `tab` route take, and what gets
// persisted as the last-used tab.
//
// A tab component may declare any of these; all are optional:
//   property var hub            - set to this panel (settings, persist, close)
//   property QtObject bar       - the bar host
//   property color foreground   - theme foreground, already resolved
//   property string fontFamily  - theme font, already resolved
//   property bool keysBlocked   - true while it owns the keyboard (inline edit)
//   function handleMove(dx, dy) - return true if the arrow key was consumed
//   function handleActivate()   - Enter / Space
//   function handleTextKey(t)   - a single printable key
//   function handleClose()      - Escape; return true to keep the panel open
//   function tabShown()         - became the visible page of an open panel
//   function tabHidden()        - stopped being it (tab switch or close)
//   function refresh()          - panel opened, or a refresh came over IPC
//   function panelClosed()      - panel dismissed; drop transient state
// Everything else is the tab's own business, including its layout: the page
// scrolls for it, so a tab only has to report an honest implicitHeight.
//
// Geometry rhythm used by every page: 8 between related items, 12 inside
// compact cards, 16 inside hero/metric surfaces, 32 for header actions and
// 36 for the header band. Surfaces inherit Style.cornerRadius from the active
// theme. Smaller values are reserved for text/icon grouping.
Panel {
  id: root
  moduleName: "kevinbsr.omahub"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- The modules. Order here is the order in the strip, and index 0 is
  //      what a fresh install opens on.
  readonly property var tabs: [
    { id: "calendar", label: "Calendar", icon: "󰃭", source: "CalendarTab.qml", minWidth: Style.space(560) },
    { id: "media", label: "Media", icon: "󰝚", source: "MediaTab.qml", minWidth: Style.space(420) },
    { id: "weather", label: "Weather", icon: "󰖐", source: "WeatherTab.qml", minWidth: Style.space(480) },
    { id: "screentime", label: "Screen", icon: "󰔟", source: "ScreenTimeTab.qml", minWidth: Style.space(400) },
    { id: "phone", label: "Phone", icon: "󰄜", source: "KdeConnectTab.qml", minWidth: Style.space(400) },
    { id: "nearby", label: "Nearby", icon: "󰀂", source: "NearbyTab.qml", minWidth: Style.space(400) },
    { id: "system", label: "System", icon: "󰍛", source: "SystemTab.qml", minWidth: Style.space(480) }
  ]

  // Weather's data layer lives in the hub service, shared by every monitor's
  // panel (it used to be one WeatherSource per panel -- three fetchers for one
  // forecast). Still exposed here because WeatherTab.qml and BarWidget.qml read
  // it through the panel, and the bar icon needs it whether or not the weather
  // page has ever been opened.
  readonly property var weather: hubService ? hubService.weather : null


  // One width for every tab, taken from the widest, so switching pages moves
  // the content and not the popup around it.
  readonly property real panelWidth: {
    var widest = 0
    for (var i = 0; i < tabs.length; i++) widest = Math.max(widest, tabs[i].minWidth || 0)
    return widest + Style.space(160)
  }

  // Which tab is up.
  //
  // Live state goes through the hub service, which every monitor's copy of this
  // panel shares; that is how the other screens learn the tab changed. It used
  // to go through shell.json, and each change cost two full plugin re-syncs of
  // every bar (see Service.qml, currentTab).
  //
  // shell.json still holds the last tab so a restart reopens it, but it is
  // only written once the panel is shut (persistTabLater), never while the
  // user is clicking. Settings are followed rather than read at construction
  // because BarWidget.qml hands them over after loading this panel, so an
  // up-front read would only ever see an empty object.
  readonly property var hubService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("kevinbsr.omahub") : null
  property int currentIndex: 0
  readonly property var currentTab: tabs[Math.max(0, Math.min(currentIndex, tabs.length - 1))]
  readonly property string currentTabId: currentTab ? String(currentTab.id) : ""
  property var activeTabItem: null
  property bool helpOpen: false
  function toggleHelp() {
    if (!helpOpen && activeTabItem && activeTabItem.keysBlocked === true) return
    helpOpen = !helpOpen
    focusKeyCatcher()
  }

  // Guarded so the panel renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function indexOfTab(id) {
    var name = String(id || "")
    for (var i = 0; i < tabs.length; i++) if (String(tabs[i].id) === name) return i
    return 0
  }

  function syncTab() {
    // The bare default before injection is an empty object; acting on it
    // would snap every panel to tab 0 on the way up.
    if (!settings || Object.keys(settings).length === 0) return
    // The service is newer than the file whenever the two disagree: the file
    // only catches up after the panel closes, and any other settings write in
    // between (the calendar's week start, the label format) would otherwise
    // snap every panel back to the stale stored tab.
    var wanted = (hubService && hubService.currentTab) ? hubService.currentTab : setting("tab", tabs[0].id)
    if (hubService && !hubService.currentTab) hubService.currentTab = String(wanted)
    var next = indexOfTab(wanted)
    if (next !== currentIndex) currentIndex = next
  }

  function selectTab(id) {
    root.helpOpen = false
    var next = indexOfTab(id)
    if (next === currentIndex) return
    currentIndex = next
    var tabId = String(tabs[next].id)
    // In memory, shared: the other monitors' panels follow through the
    // Connections below. Without the service (it is keepLoaded, so this should
    // not happen) fall back to the old, slow path rather than losing the sync.
    if (hubService) hubService.currentTab = tabId
    else persistSettings({ tab: tabId })
  }

  Connections {
    target: root.hubService
    ignoreUnknownSignals: true
    function onCurrentTabChanged() {
      var next = root.indexOfTab(root.hubService.currentTab)
      if (next !== root.currentIndex) root.currentIndex = next
    }
  }

  // Remember the tab across restarts without paying for it mid-interaction.
  // A shell.json write stalls the QML thread on every bar for ~200 ms, so it
  // waits until the panel is shut and its close animation is over, and it is
  // skipped entirely when the stored tab already matches.
  Timer {
    id: persistTabLater
    interval: 1500
    onTriggered: {
      if (root.opened || !root.currentTabId) return
      var changes = {}
      if (String(root.setting("tab", "")) !== root.currentTabId) changes.tab = root.currentTabId
      if (Object.keys(changes).length) root.persistSettings(changes)
    }
  }

  function cycleTab(direction) {
    var count = tabs.length
    if (count < 2) return
    selectTab(tabs[(currentIndex + direction + count) % count].id)
  }

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave a tab's inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (activeTabItem && typeof activeTabItem.panelClosed === "function") activeTabItem.panelClosed()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (activeTabItem && typeof activeTabItem.refresh === "function") activeTabItem.refresh()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    // The shell started handing plugins a PluginBarApi, where
    // centerHoverRevealSuppressed is readonly (Ui/PluginBarApi.qml:26): a
    // direct assignment throws TypeError. Since close() called this BEFORE
    // controller.hide(), the exception aborted the function and the panel
    // never closed, leaving the omarchy-keyboard-panel layer stuck on
    // screen at 1536x864. Fixed by copying the pattern from Omarchy's own
    // panels (plugins/panels/clock/Panel.qml): prefer the API's setter and
    // keep the direct assignment only as a fallback for the real Bar.
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write these keys straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    // Other writes (week start, label format) carry the tab too, so they never
    // put a stale one back on disk behind the service's newer value.
    if (!("tab" in values) && root.currentTabId) entry.tab = root.currentTabId

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Kept on the panel rather than the calendar because the bar widget's IPC
  // route reaches for it by name and should not have to know which tab owns
  // it. Delegates to whichever tab does.
  function toggleWeekStart() {
    var page = pageAt(indexOfTab("calendar"))
    if (page && typeof page.toggleWeekStart === "function") page.toggleWeekStart()
  }

  // ---- Which page is actually on screen. A module that costs something to
  //      show — a discovery sweep, a poll — needs to be told when it stops
  //      being looked at, which is a different moment from the panel closing:
  //      switching tabs hides one page and shows another with the panel still
  //      open. Panels that cost nothing simply never define the hooks.
  property var shownTabItem: null

  function updateShownTab() {
    var next = (root.opened && root.activeTabItem) ? root.activeTabItem : null
    if (next === shownTabItem) return
    if (shownTabItem && typeof shownTabItem.tabHidden === "function") shownTabItem.tabHidden()
    shownTabItem = next
    if (shownTabItem && typeof shownTabItem.tabShown === "function") shownTabItem.tabShown()
  }

  onOpenedChanged: {
    if (!opened) root.helpOpen = false
    updateShownTab()
    if (opened) persistTabLater.stop()
    else persistTabLater.restart()
  }
  onActiveTabItemChanged: updateShownTab()

  // Hand the keyboard back to the panel after a tab's inline editor closes.
  function focusKeyCatcher() {
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function pageAt(index) {
    var entry = pages.itemAt(index)
    return entry && entry.tabItem ? entry.tabItem : null
  }

  // ---- Scrolling the current page. A tall module should not have to own a
  //      Flickable to be reachable by keyboard, so the panel drives the one
  //      it already wraps every page in.
  function scrollActivePage(delta) {
    var page = pages.itemAt(currentIndex)
    if (!page || page.contentHeight <= page.height) return
    page.contentY = Math.max(0, Math.min(page.contentHeight - page.height, page.contentY + delta))
  }

  function ensureActiveRectVisible(y, height) {
    var page = pages.itemAt(currentIndex)
    if (!page) return
    var next = page.contentY
    if (y < next) next = y
    else if (y + height > next + page.height) next = y + height - page.height
    page.contentY = Math.max(0, Math.min(Math.max(0, page.contentHeight - page.height), next))
  }

  function scrollActivePageToEnd() {
    var page = pages.itemAt(currentIndex)
    if (!page || page.contentHeight <= page.height) return
    page.contentY = page.contentHeight - page.height
  }

  onSettingsChanged: syncTab()

  onCurrentIndexChanged: Qt.callLater(function() {
    root.activeTabItem = root.pageAt(root.currentIndex)
    if (root.opened) root.refresh()
  })

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    // fittedContentWidth caps the OUTER card. Account for its insets and
    // the scrollbar gutter so the widest page gets the width it requested.
    contentWidth: panel.fittedContentWidth(root.panelWidth + panel.padding * 2
      + Border.left(panel.borderSpec) + Border.right(panel.borderSpec) + Style.space(10))
    // Stable page viewport; long pages scroll and smaller displays still clamp.
    contentHeight: panel.fittedContentHeight(Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: !root.helpOpen && root.activeTabItem ? root.activeTabItem.keysBlocked === true : false

      // Arrows, Enter and printable keys belong to whatever is on screen;
      // the panel only keeps the keys that move between pages. A tab that
      // does not consume a key returns falsy and the panel lets it go.
      // A page that does not claim the key gets the panel's default, which
      // is to scroll it — the sane fallback for a module too tall to fit.
      onMoveRequested: function(dx, dy) {
        if (root.helpOpen) { shortcutHelp.scroll(dy * Style.space(28)); return }
        var item = root.activeTabItem
        if (item && typeof item.handleMove === "function" && item.handleMove(dx, dy) === true) return
        if (dy !== 0) root.scrollActivePage(dy * Style.space(24))
      }
      onActivateRequested: {
        if (root.helpOpen) return
        if (root.activeTabItem && typeof root.activeTabItem.handleActivate === "function")
          root.activeTabItem.handleActivate()
      }
      // A page may back out of its own layer first — a confirmation, an
      // open composer — and only fall through to closing once it has none
      // left. Pages without that state never define handleClose.
      onCloseRequested: {
        if (root.helpOpen) { root.helpOpen = false; return }
        var item = root.activeTabItem
        if (item && typeof item.handleClose === "function" && item.handleClose() === true) return
        root.close()
      }
      // Tab walks the hub's own pages first — with the modules folded into
      // one panel, that is what "next" means from inside it. Only from the
      // last page does it hand off to the next panel on the bar.
      onTabRequested: function(direction) {
        var next = root.currentIndex + direction
        if (next < 0 || next >= root.tabs.length) {
          if (root.switchPanel(direction)) return
          root.cycleTab(direction)
          return
        }
        root.selectTab(root.tabs[next].id)
      }
      onTextKey: function(t) {
        if (t === "?") { root.toggleHelp(); return }
        // Digits jump straight to a page, so a hub with five modules is
        // still one keystroke deep.
        var digit = parseInt(t, 10)
        if (!isNaN(digit) && digit >= 1 && digit <= root.tabs.length) {
          root.selectTab(root.tabs[digit - 1].id)
          return
        }
        if (root.helpOpen) return
        if (root.activeTabItem && typeof root.activeTabItem.handleTextKey === "function")
          root.activeTabItem.handleTextKey(t)
      }

      // A quiet navigation rail keeps all destinations in view. The
      // content retains its own scroll position and the original key routes.
      Column {
        id: navigation
        anchors.top: parent.top
        anchors.left: parent.left
        width: Style.space(140)
        spacing: Style.space(4)

        Repeater {
          model: root.tabs
          delegate: Rectangle {
            id: destination
            required property var modelData
            required property int index
            readonly property bool selected: root.currentIndex === index
            width: navigation.width
            height: Style.space(42)
            radius: Style.cornerRadius
            color: selected
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
              : (navMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent")
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.label
            Accessible.selected: selected
            Accessible.onPressAction: root.selectTab(modelData.id)

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: 2
              height: Style.space(18)
              radius: Math.min(width / 2, Style.cornerRadius)
              visible: destination.selected
              color: Color.accent
            }
            Text {
              textFormat: Text.PlainText
              id: navIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              text: destination.modelData.icon
              color: destination.selected ? Color.accent : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.icon
            }
            Text {
              textFormat: Text.PlainText
              anchors.left: navIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: destination.modelData.label
              elide: Text.ElideRight
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.weight: destination.selected ? Font.DemiBold : Font.Normal
            }
            MouseArea {
              id: navMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectTab(destination.modelData.id)
              PanelToolTip {
                visible: navMouse.containsMouse
                text: destination.modelData.label + " · " + (destination.index + 1)
                fontFamily: root.contentFontFamily
              }
            }
          }
        }
      }

      PanelActionButton {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(9)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(8)
        size: Style.space(32)
        iconText: "?"
        tooltipText: "Keyboard shortcuts · ?"
        enabled: root.helpOpen || !root.activeTabItem || root.activeTabItem.keysBlocked !== true
        hasCursor: root.helpOpen
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onClicked: root.toggleHelp()
      }

      // ---- Pages. One Flickable per tab so a module only has to report an
      //      honest implicitHeight and the panel handles a screen too short
      //      to show it. Loaded on first visit and kept after, so stepping
      //      back to the calendar lands on the month you left it on.
      Item {
        id: stack
        anchors.top: parent.top
        anchors.left: navigation.right
        anchors.leftMargin: Style.space(20)
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        readonly property real contentHeight: {
          var item = root.activeTabItem
          return item ? item.implicitHeight : 0
        }

        Repeater {
          id: pages
          model: root.tabs

          Flickable {
            id: page
            required property var modelData
            required property int index

            // Loaded on first visit, kept afterwards: a module that has to
            // rebuild its state on every tab switch is a module that loses
            // it, and none of them are expensive enough to be worth that.
            property bool everShown: index === root.currentIndex
            readonly property var tabItem: tabLoader.item

            anchors.fill: parent
            anchors.bottomMargin: Style.space(10)
            visible: index === root.currentIndex && !root.helpOpen
            enabled: visible
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: tabLoader.width
            contentHeight: tabLoader.height
            interactive: contentHeight > height || contentWidth > width

            Controls.ScrollBar.vertical: HubScrollBar {
              foreground: root.contentForeground
              visible: page.visible && size < 1
            }
            Controls.ScrollBar.horizontal: HubScrollBar {
              parent: stack
              x: page.x
              y: page.height
              width: page.width
              foreground: root.contentForeground
              visible: page.visible && size < 1
            }

            onVisibleChanged: if (visible) everShown = true

            Loader {
              id: tabLoader
              active: page.everShown
              source: page.everShown ? Qt.resolvedUrl(String(page.modelData.source)) : ""
              // Never narrower than the module asked for. The popup width is
              // capped to what the screen allows, and a fixed-width grid
              // would otherwise lose its last column off the edge instead of
              // scrolling.
              width: Math.max(page.width - Style.space(10), page.modelData.minWidth || 0)
              height: item ? item.implicitHeight : 0

              onLoaded: {
                if ("hub" in item) item.hub = root
                if ("bar" in item) item.bar = root.bar
                if ("foreground" in item) item.foreground = Qt.binding(function() { return root.contentForeground })
                if ("fontFamily" in item) item.fontFamily = Qt.binding(function() { return root.contentFontFamily })
                if (page.index === root.currentIndex) {
                  root.activeTabItem = item
                  if (root.opened) root.refresh()
                }
              }
            }
          }
        }
      }

      ShortcutHelp {
        id: shortcutHelp
        anchors.fill: stack
        visible: root.helpOpen
        pageId: root.currentTabId
        pageLabel: root.currentTab.label
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onDismissed: { root.helpOpen = false; root.focusKeyCatcher() }
      }
    }
  }

  Component.onCompleted: Qt.callLater(function() { root.activeTabItem = root.pageAt(root.currentIndex) })
}
