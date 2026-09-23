import QtQuick
import qs.Commons
import qs.Ui
import "ScreenTimeModel.js" as ScreenTimeModel

// Daily focused-window time, backed by the installed agx.screen-time engine.
Item {
  id: root

  property var hub: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool shown: false
  property bool historyExpanded: false
  property string selectedKey: ""
  property string knownTodayKey: ""
  property double nowMs: Date.now()

  readonly property var integrationHost: hub && hub.hubService ? hub.hubService.integrations : null
  readonly property var service: integrationHost ? integrationHost.screenTime : null
  // Enabled and loaded, but the loader hit an error -- distinct from never
  // having been turned on, which "Enable activity tracking" already covers.
  readonly property bool serviceFailed: !!(integrationHost && integrationHost.screenTimeFailed)
  readonly property bool serviceReady: !!(service && service.ready === true)
  readonly property var today: service ? service.today : null
  readonly property var days: service ? service.days : ({})
  readonly property string todayKey: serviceReady ? String(service.todayKey || "") : ""
  readonly property string yesterdayKey: ScreenTimeModel.prevKey(todayKey)
  readonly property var selectedDay: serviceReady
    ? ScreenTimeModel.dayFor(days, today, selectedKey || todayKey, todayKey) : ({ total: 0, apps: ({}) })
  readonly property double selectedTotal: Number(selectedDay.total) || 0
  readonly property double todayTotal: serviceReady && today ? Number(today.total) || 0 : 0
  readonly property double yesterdayTotal: serviceReady ? ScreenTimeModel.totalFor(days, yesterdayKey) : 0
  readonly property double average7: serviceReady ? ScreenTimeModel.averagePreviousDays(days, todayKey, 7) : 0
  readonly property var apps: serviceReady
    ? ScreenTimeModel.groupedApps(ScreenTimeModel.appList(selectedDay), ScreenTimeModel.DONUT_MAX_SLICES) : []
  readonly property var segments: ScreenTimeModel.arcSegments(apps)
  readonly property var sliceColors: ScreenTimeModel.sliceColors(apps.length, Color.accent)
  readonly property var weekTrend: serviceReady ? ScreenTimeModel.weekTrend(days, todayKey) : []
  readonly property var historyRows: serviceReady ? ScreenTimeModel.historyRows(days, today, todayKey) : []
  readonly property var busiest: serviceReady ? ScreenTimeModel.busiestWeekDay(days, todayKey) : ({ key: "", total: 0 })
  readonly property double weekMax: {
    var max = 0
    for (var i = 0; i < weekTrend.length; i++) max = Math.max(max, Number(weekTrend[i].ms) || 0)
    return max
  }
  readonly property string activeApp: integrationHost ? String(integrationHost.screenSessionApp || "") : ""
  readonly property double activeSince: integrationHost ? Number(integrationHost.screenSessionStartedAt) || 0 : 0
  readonly property double activeElapsed: activeSince > 0 ? Math.max(0, nowMs - activeSince) : 0
  readonly property string selectedLabel: selectedKey === todayKey ? "Today"
    : selectedKey === yesterdayKey ? "Yesterday" : formatKey(selectedKey, "ddd, MMM d")
  readonly property string selectedDateLabel: formatKey(selectedKey, "MMMM d, yyyy")
  readonly property string todayComparison: ScreenTimeModel.comparisonText(todayTotal, average7)
  readonly property int ringSize: Style.space(104)
  readonly property int ringWidth: Style.space(13)
  readonly property real ringRadius: ringSize / 2 - ringWidth / 2

  implicitHeight: content.implicitHeight

  onTodayKeyChanged: {
    var followToday = selectedKey === "" || selectedKey === knownTodayKey
    knownTodayKey = todayKey
    if (followToday) selectedKey = todayKey
  }

  function formatKey(key, pattern) {
    var parts = String(key || "").split("-")
    if (parts.length !== 3) return ""
    var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12)
    return isNaN(date.getTime()) ? "" : Qt.formatDate(date, pattern)
  }
  function selectDay(key, closeHistory) {
    var value = String(key || "")
    if (value === "" || value > todayKey) return
    selectedKey = value
    if (closeHistory) {
      historyExpanded = false
      if (hub) Qt.callLater(function() { hub.scrollActivePage(-100000) })
    }
  }
  function moveDay(delta) { selectDay(ScreenTimeModel.shiftKey(selectedKey || todayKey, delta), false) }
  function toggleHistory() {
    historyExpanded = !historyExpanded
    if (historyExpanded && hub) Qt.callLater(function() { hub.scrollActivePage(Style.space(120)) })
  }
  function tabShown() { shown = true; nowMs = Date.now() }
  function tabHidden() { shown = false }
  function panelClosed() { shown = false; historyExpanded = false }
  function handleMove(dx, dy) {
    if (dx !== 0) { moveDay(dx); return true }
    return false
  }
  function handleTextKey(text) {
    var key = String(text || "").toLowerCase()
    if (!service && key === "a") { trackerSetup.activate(); return true }
    if (key === "t") { selectDay(todayKey, false); return true }
    if (key === "h") { toggleHistory(); return true }
    return false
  }
  function sliceColor(index, alpha) {
    var hex = String(sliceColors[index] || Color.accent).replace(/[#\s]/g, "")
    return Qt.rgba(parseInt(hex.substr(0, 2), 16) / 255,
      parseInt(hex.substr(2, 2), 16) / 255,
      parseInt(hex.substr(4, 2), 16) / 255, alpha)
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.shown && root.activeApp !== ""
    onTriggered: root.nowMs = Date.now()
  }

  component SummaryCard: Rectangle {
    id: card
    property string label: ""
    property string value: ""
    property string detail: ""
    property string dayKey: ""
    property bool selected: dayKey !== "" && dayKey === root.selectedKey
    height: Style.space(58)
    radius: Style.cornerRadius
    color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
      : cardMouse.containsMouse && dayKey !== "" ? Style.hoverFillFor(root.foreground, Color.accent)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
    border.width: selected ? Style.spacing.hairline : 0
    border.color: Color.accent
    Column {
      anchors.left: parent.left; anchors.right: parent.right
      anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(1)
      Text { textFormat: Text.PlainText; width: parent.width; text: card.label; elide: Text.ElideRight; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      Text { textFormat: Text.PlainText; width: parent.width; text: card.value; elide: Text.ElideRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.weight: Font.DemiBold }
      Text { textFormat: Text.PlainText; width: parent.width; text: card.detail; elide: Text.ElideRight; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.58); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    }
    MouseArea {
      id: cardMouse; anchors.fill: parent; enabled: card.dayKey !== ""; hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.selectDay(card.dayKey, false)
    }
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(8)

    Item {
      width: parent.width; height: Style.space(36)
      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        text: "Screen time"; color: root.foreground; font.family: root.fontFamily
        font.pixelSize: Style.font.title; font.weight: Font.DemiBold
      }
      Row {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(8)
        Button { height: Style.space(32); text: "Today"; enabled: root.selectedKey !== root.todayKey; tooltipText: "Select today · T"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.selectDay(root.todayKey, false) }
        Button { height: Style.space(32); text: root.historyExpanded ? "Close history" : "History"; tooltipText: "Retained daily history · H"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.toggleHistory() }
      }
    }

    Rectangle {
      visible: root.activeApp !== ""
      width: parent.width; height: visible ? Style.space(42) : 0; radius: Style.cornerRadius
      color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.08)
      Rectangle { width: Style.space(6); height: width; radius: width / 2; color: Color.accent; anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
      Column {
        anchors.left: parent.left; anchors.leftMargin: Style.space(28); anchors.right: activeTime.left; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(1)
        Text { textFormat: Text.PlainText; width: parent.width; text: "ACTIVE NOW"; elide: Text.ElideRight; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1 }
        Text { textFormat: Text.PlainText; width: parent.width; text: ScreenTimeModel.displayName(root.activeApp); elide: Text.ElideRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      }
      Text { textFormat: Text.PlainText; id: activeTime; anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: ScreenTimeModel.fmt(root.activeElapsed); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    }

    Text {
      textFormat: Text.PlainText
      // Enabled-but-broken is its own state, and the one thing it must never
      // read as: turning tracking on again does nothing when it is already
      // on. See HubIntegrations.qml's screenTimeFailed.
      visible: root.serviceFailed
      width: parent.width
      text: "Screen Time is enabled, but failed to load. Disable and re-enable it in the Hub's settings, or check the plugin — a notification named which one failed."
      color: Color.urgent
      font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.Wrap
    }
    Text {
      textFormat: Text.PlainText
      visible: !root.serviceReady && !root.serviceFailed
      width: parent.width
      text: !root.service ? (trackerSetup.configuredEnabled ? "Starting activity tracking…" : "Enable activity tracking to collect focused-window time.") : "Loading history…"
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
      font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.Wrap
    }
    IntegrationSetup {
      id: trackerSetup; visible: !root.service && !root.serviceFailed; width: parent.width
      pluginId: "agx.screen-time"; actionText: "Enable tracking"
      foreground: root.foreground; fontFamily: root.fontFamily
    }

    Row {
      visible: root.serviceReady
      width: parent.width; spacing: Style.space(8)
      SummaryCard { width: (parent.width - parent.spacing * 2) / 3; label: "TODAY"; value: ScreenTimeModel.fmt(root.todayTotal); detail: root.average7 > 0 ? ScreenTimeModel.fmtDelta(root.todayTotal - root.average7) + " vs avg" : "Building baseline"; dayKey: root.todayKey }
      SummaryCard { width: (parent.width - parent.spacing * 2) / 3; label: "YESTERDAY"; value: ScreenTimeModel.fmt(root.yesterdayTotal); detail: root.yesterdayTotal > 0 ? ScreenTimeModel.fmtDelta(root.todayTotal - root.yesterdayTotal) + " today" : "No baseline"; dayKey: root.yesterdayKey }
      SummaryCard { width: (parent.width - parent.spacing * 2) / 3; label: "7-DAY AVG"; value: ScreenTimeModel.fmt(root.average7); detail: "Completed days" }
    }

    Item {
      visible: root.serviceReady
      width: parent.width; height: visible ? Style.space(22) : 0
      PanelActionButton { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; iconText: "‹"; tooltipText: "Previous day · Left"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.moveDay(-1) }
      Column {
        anchors.centerIn: parent; spacing: 0
        Text { textFormat: Text.PlainText; anchors.horizontalCenter: parent.horizontalCenter; text: root.selectedLabel; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
        Text { textFormat: Text.PlainText; anchors.horizontalCenter: parent.horizontalCenter; text: root.selectedDateLabel; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      }
      PanelActionButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; iconText: "›"; enabled: root.selectedKey < root.todayKey; tooltipText: "Next day · Right"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.moveDay(1) }
    }

    Item {
      visible: root.serviceReady && root.apps.length > 0
      width: parent.width; implicitHeight: visible ? Math.max(root.ringSize, legend.implicitHeight) : 0
      Item {
        id: donut; width: root.ringSize; height: root.ringSize; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        Canvas {
          id: donutCanvas; anchors.fill: parent
          Connections {
            target: root
            function onSegmentsChanged() { donutCanvas.requestPaint() }
            function onSliceColorsChanged() { donutCanvas.requestPaint() }
          }
          onPaint: {
            var ctx = getContext("2d"); ctx.reset(); var total = root.segments
            for (var i = 0; i < total.length; i++) {
              var segment = total[i]; ctx.lineWidth = root.ringWidth; ctx.strokeStyle = root.sliceColor(i, 1)
              ctx.beginPath(); ctx.arc(width / 2, height / 2, root.ringRadius, segment.startAngle * Math.PI / 180, (segment.startAngle + segment.sweepAngle) * Math.PI / 180, false); ctx.stroke()
            }
          }
        }
        Column {
          anchors.centerIn: parent; width: parent.width * 0.62; spacing: Style.space(1)
          Text { textFormat: Text.PlainText; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.selectedLabel.toUpperCase(); elide: Text.ElideRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          Text { textFormat: Text.PlainText; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: ScreenTimeModel.fmt(root.selectedTotal); color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.68); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        }
      }
      Column {
        id: legend; anchors.left: donut.right; anchors.leftMargin: Style.space(16); anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(4)
        Repeater {
          model: root.apps
          Item {
            required property var modelData; required property int index
            width: parent.width; implicitHeight: Math.max(nameText.implicitHeight, timeText.implicitHeight)
            Rectangle { width: Style.space(7); height: width; radius: width / 2; color: root.sliceColors[index] || Color.accent; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
            Text { textFormat: Text.PlainText; id: nameText; anchors.left: parent.left; anchors.leftMargin: Style.space(14); anchors.right: timeText.left; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; text: ScreenTimeModel.displayName(modelData.app); elide: Text.ElideRight; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.68); font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text { textFormat: Text.PlainText; id: timeText; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: ScreenTimeModel.fmt(modelData.ms); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
          }
        }
      }
    }
    Text {
      textFormat: Text.PlainText
      visible: root.serviceReady && root.apps.length === 0
      width: parent.width; text: "No focused-window activity recorded for " + root.selectedLabel.toLowerCase() + "."
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62); font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.italic: true
    }

    PanelSectionHeader { visible: root.serviceReady; text: "LAST 7 DAYS"; foreground: root.foreground; fontFamily: root.fontFamily }
    Row {
      visible: root.serviceReady
      width: parent.width; height: visible ? Style.space(62) : 0; spacing: Style.space(5)
      Repeater {
        model: root.weekTrend
        Rectangle {
          id: trendDay
          required property var modelData
          width: (parent.width - parent.spacing * 6) / 7; height: parent.height; radius: Style.cornerRadius
          color: modelData.key === root.selectedKey ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.1)
            : trendMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
          Item {
            width: parent.width; height: Style.space(38); anchors.top: parent.top
            Rectangle {
              width: parent.width * 0.38; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
              radius: Math.min(height / 2, Style.cornerRadius); color: trendDay.modelData.isToday ? Color.accent : root.sliceColor(0, 0.3)
              height: trendDay.modelData.ms <= 0 || root.weekMax <= 0 ? Style.space(2) : Math.max(Style.space(2), parent.height * Number(trendDay.modelData.ms) / root.weekMax)
            }
          }
          Text { textFormat: Text.PlainText; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(3); text: modelData.label; color: root.foreground; opacity: modelData.key === root.selectedKey || modelData.isToday ? 1 : 0.55; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          MouseArea { id: trendMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectDay(trendDay.modelData.key, false) }
          PanelToolTip { visible: trendMouse.containsMouse; text: root.formatKey(modelData.key, "dddd, MMM d") + " · " + ScreenTimeModel.fmt(modelData.ms); fontFamily: root.fontFamily }
        }
      }
    }

    Rectangle {
      visible: root.serviceReady
      width: parent.width; height: visible ? Style.space(44) : 0; radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
      Text { textFormat: Text.PlainText; anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.right: busiestText.left; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: root.todayComparison; elide: Text.ElideRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
      Text { textFormat: Text.PlainText; id: busiestText; anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: root.busiest.total > 0 ? "Peak: " + ScreenTimeModel.relativeDayLabel(root.busiest.key, root.todayKey) + " · " + ScreenTimeModel.fmt(root.busiest.total) : ""; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62); font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    }

    Column {
      visible: root.historyExpanded && root.historyRows.length > 0
      width: parent.width; spacing: Style.space(8)
      PanelSectionHeader { text: "RETAINED HISTORY"; foreground: root.foreground; fontFamily: root.fontFamily }
      Grid {
        width: parent.width; columns: 2; spacing: Style.space(6)
        Repeater {
          model: root.historyRows
          Rectangle {
            id: historyRow
            required property var modelData
            width: (parent.width - parent.spacing) / 2; height: Style.space(36); radius: Style.cornerRadius
            color: modelData.key === root.selectedKey ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
              : historyMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)
            Text { textFormat: Text.PlainText; anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: root.formatKey(historyRow.modelData.key, "ddd, MMM d"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text { textFormat: Text.PlainText; anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: ScreenTimeModel.fmt(historyRow.modelData.ms); color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.65); font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            MouseArea { id: historyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectDay(historyRow.modelData.key, true) }
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.serviceReady; width: parent.width
      text: "Focused-window time · lock screen and idle periods are excluded"
      horizontalAlignment: Text.AlignHCenter; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.48)
      font.family: root.fontFamily; font.pixelSize: Style.font.caption
    }
  }
}
