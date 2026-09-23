import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ClockModel.js" as ClockModel

// Calendar selection, clipboard actions and persistent progress indicators.
Item {
  id: root

  // ---- Tab contract, injected by Panel.qml.
  property var hub: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property bool keysBlocked: root.editingLife

  function setting(name, fallback) {
    return hub && typeof hub.setting === "function" ? hub.setting(name, fallback) : fallback
  }

  function persist(values) {
    if (hub && typeof hub.persistSettings === "function") hub.persistSettings(values)
  }

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: ClockModel.keyForDate(today)
  property date selectedDate: new Date(today.getFullYear(), today.getMonth(), today.getDate(), 12)
  readonly property string selectedKey: ClockModel.keyForDate(selectedDate)
  readonly property int selectedDistance: ClockModel.calendarDayDistance(today, selectedDate)
  readonly property string relativeDate: selectedDistance === 0 ? "Today"
    : selectedDistance === 1 ? "Tomorrow" : selectedDistance === -1 ? "Yesterday"
    : selectedDistance > 0 ? "In " + selectedDistance + " days" : Math.abs(selectedDistance) + " days ago"
  property string copiedFormat: ""
  property string copyError: ""
  onSelectedDateChanged: { copiedFormat = ""; copyError = "" }

  // The header and grid follow the selected date.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: ClockModel.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: ClockModel.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Double-click the life bar to edit it, or the year bar to set it up
  // when no birth year is configured. A second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: ClockModel.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: ClockModel.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: ClockModel.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: ClockModel.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: ClockModel.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: ClockModel.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property string nextWeekStartLabel: Qt.locale().dayName(ClockModel.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: ClockModel.weekdayOrder(weekStart)
  readonly property var weeks: ClockModel.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property int cellWidth: Math.floor((root.width - weekColumnWidth - gutterWidth - cellSpacing * 8) / 7)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  implicitHeight: calendarColumn.implicitHeight
  implicitWidth: Style.space(560)

  // ---- Tab contract: keyboard.
  function handleMove(dx, dy) {
    selectDate(new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + dx + dy * 7, 12))
    return true
  }

  function handleActivate() {
    copyDate("local")
    return true
  }

  function handleTextKey(t) {
    if (t === "[") moveMonth(-1)
    else if (t === "]") moveMonth(1)
    else if (t === "{") moveYear(-1)
    else if (t === "}") moveYear(1)
    else if (t === "t" || t === "T") goToToday()
    else if (t === "w" || t === "W") toggleWeekStart()
    else if (t === "c" || t === "C") copyDate("local")
    else if (t === "i" || t === "I") copyDate("iso")
    else return false
    return true
  }

  function updateToday(value) {
    var follow = root.selectedKey === root.todayKey
    root.today = value
    if (follow) goToToday()
  }
  function refresh() { updateToday(new Date()) }
  function panelClosed() {
    if (root.editingLife) root.cancelEditingLife()
    root.copiedFormat = ""
  }
  function selectDate(date) {
    if (isNaN(date.getTime())) return
    root.selectedDate = date
    root.viewYear = date.getFullYear()
    root.viewMonth = date.getMonth()
  }
  function goToToday() {
    selectDate(new Date(today.getFullYear(), today.getMonth(), today.getDate(), 12))
  }
  function moveMonth(delta) { selectDate(ClockModel.shiftCalendarMonth(selectedDate, delta)) }
  function moveYear(delta) { moveMonth(delta * 12) }
  function copyDate(format) {
    if (clipboardWriter.running) return
    copiedFormat = ""
    copyError = ""
    clipboardWriter.requestedFormat = format
    clipboardWriter.dateKey = root.selectedKey
    clipboardWriter.value = Qt.formatDate(root.selectedDate, format === "iso" ? "yyyy-MM-dd" : "dd/MM/yyyy")
    clipboardWriter.running = true
  }
  Process {
    id: clipboardWriter
    property string requestedFormat: ""
    property string dateKey: ""
    property string value: ""
    command: ["wl-copy", "--", value]
    onExited: function(code) {
      if (dateKey !== root.selectedKey) return
      if (code === 0) { root.copiedFormat = requestedFormat; copiedTimer.restart() }
      else root.copyError = "Could not copy the date."
    }
  }
  Timer { id: copiedTimer; interval: 1800; onTriggered: root.copiedFormat = "" }

  function setWeekStart(day) {
    var next = ClockModel.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persist({ weekStartDay: ClockModel.weekStartSettingName(next) })
  }

  function toggleWeekStart() {
    setWeekStart(ClockModel.toggledWeekStart(root.weekStart))
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      if (root.hub) root.hub.scrollActivePageToEnd()
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    if (hub && typeof hub.focusKeyCatcher === "function") hub.focusKeyCatcher()
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  function commitLife() {
    var born = ClockModel.parseBirthYear(bornField.text, today.getFullYear())
    var span = ClockModel.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persist({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  // Locale short day names, trimmed of the trailing period some locales
  // carry ("man." -> "MAN") so the header row stays a clean band of caps.
  function weekdayLabel(weekday) {
    return String(Qt.locale().dayName(weekday, Locale.ShortFormat)).replace(/\.$/, "").toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: if (ClockModel.keyForDate(clock.date) !== root.todayKey) root.updateToday(clock.date)
  }

  Column {
    id: calendarColumn
    width: parent.width
    spacing: Style.space(8)

    Item {
      width: parent.width
      height: Style.space(36)
      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: monthActions.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDate(root.viewDate, "MMMM yyyy")
        elide: Text.ElideRight
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
      }
      Row {
        id: monthActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        PanelActionButton {
          size: Style.space(32)
          iconText: "‹"; tooltipText: "Previous month · ["
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: root.moveMonth(-1)
        }
        Button {
          height: Style.space(32)
          text: "Today"; tooltipText: "Select today · T"
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: root.goToToday()
        }
        PanelActionButton {
          size: Style.space(32)
          iconText: "›"; tooltipText: "Next month · ]"
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: root.moveMonth(1)
        }
      }
    }

    // ---- Month grid: week numbers down a gutter on the left, then the
    //      seven day columns. Always six rows, so the page is exactly as
    //      tall in February as it is in August.
    Item {
      width: parent.width
      height: gridColumn.y + gridColumn.height

      WheelHandler {
        onWheel: function(event) {
          // Horizontal wheels and touchpad side-scrolls report y === 0;
          // without this they would every one read as "next month".
          if (event.angleDelta.y === 0) return
          root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
        }
      }

      Column {
        id: gridColumn
        y: Style.space(8)
        anchors.left: parent.left
        spacing: Style.space(3)

        Row {
          id: headerRow
          spacing: root.cellSpacing

          // The week-number heading doubles as the week-start toggle. It is
          // the one control in the page whose meaning is not self-evident,
          // so it carries a tooltip naming the day the click will switch to.
          Rectangle {
            width: root.weekColumnWidth
            height: Style.space(16)
            radius: Style.cornerRadius
            color: weekStartMouse.containsMouse
              ? Style.hoverFillFor(root.foreground, Color.accent)
              : "transparent"

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "W"
              color: weekStartMouse.containsMouse
                ? Style.hoverStateColor(root.foreground, Color.accent)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.52)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            MouseArea {
              id: weekStartMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleWeekStart()
            }

            PanelToolTip {
              visible: weekStartMouse.containsMouse
              text: "Start weeks on " + root.nextWeekStartLabel
              fontFamily: root.fontFamily
            }
          }

          Item {
            width: root.gutterWidth
            height: Style.space(16)
          }

          Repeater {
            model: root.weekdays

            Text {
              textFormat: Text.PlainText
              required property var modelData
              width: root.cellWidth
              height: Style.space(16)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: root.weekdayLabel(modelData)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }
          }
        }

        Repeater {
          model: root.weeks

          Row {
            required property var modelData
            spacing: root.cellSpacing

            Text {
              textFormat: Text.PlainText
              width: root.weekColumnWidth
              height: root.cellHeight
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: modelData.week
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.52)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Item {
              width: root.gutterWidth
              height: root.cellHeight
            }

            Repeater {
              model: modelData.days

              Rectangle {
                id: dayCell
                required property var modelData
                readonly property bool selected: modelData.key === root.selectedKey

                width: root.cellWidth
                height: root.cellHeight
                radius: Style.cornerRadius
                color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
                  : dayMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                Accessible.role: Accessible.Button
                Accessible.name: Qt.formatDate(new Date(modelData.year, modelData.month, modelData.day, 12), "dddd, d MMMM yyyy")
                Accessible.selected: selected
                Accessible.onPressAction: root.selectDate(new Date(modelData.year, modelData.month, modelData.day, 12))
                MouseArea {
                  id: dayMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var date = new Date(dayCell.modelData.year, dayCell.modelData.month, dayCell.modelData.day, 12)
                    Qt.callLater(function() { root.selectDate(date) })
                  }
                }
                border.width: modelData.today ? Style.spacing.hairline : 0
                border.color: Style.normalBorderFor(root.foreground, Color.accent)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: modelData.day
                  color: dayCell.selected ? Color.accent : modelData.inMonth
                    ? (modelData.weekend ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7) : root.foreground)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.38)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: modelData.today
                }
              }
            }
          }
        }
      }

      // Hairline down the week-number gutter, drawn only beside the day rows
      // so it does not cut through the header band.
      Rectangle {
        x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
        y: gridColumn.y + headerRow.height + gridColumn.spacing
        width: Style.spacing.hairline
        height: gridColumn.height - headerRow.height - gridColumn.spacing
        color: root.foreground
        opacity: 0.1
      }
    }

    Rectangle {
      width: parent.width
      height: Math.max(selectionLabels.implicitHeight, copyActions.implicitHeight) + Style.space(24)
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
      Column {
        id: selectionLabels
        x: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - copyActions.width - Style.space(36)
        spacing: Style.space(6)
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: Qt.formatDate(root.selectedDate, "dddd · dd/MM/yyyy")
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.copyError || root.relativeDate
          elide: Text.ElideRight
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.65)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
      Row {
        id: copyActions
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        Button {
          text: root.copiedFormat === "local" ? "Copied" : "Copy date"
          tooltipText: "dd/mm/yyyy · C or Enter"
          enabled: !clipboardWriter.running
          foreground: root.foreground
          onClicked: root.copyDate("local")
        }
        Button {
          text: root.copiedFormat === "iso" ? "Copied" : "ISO"
          tooltipText: "yyyy-mm-dd · I"
          enabled: !clipboardWriter.running
          foreground: root.foreground
          onClicked: root.copyDate("iso")
        }
      }
    }

    Column {
      id: progressSection
      width: parent.width
      spacing: Style.space(8)
    // ---- Year progress, always visible below the selected date.
    Item {
      width: parent.width
      height: yearBlock.y + yearBlock.height

      Item {
        id: yearBlock
        y: Style.space(6)
        anchors.horizontalCenter: parent.horizontalCenter
        width: gridColumn.width
        height: root.editingLife ? Style.space(38) : Math.max(yearLabel.implicitHeight, Style.space(10))

        TapHandler {
          enabled: !root.editingLife && root.birthYear <= 0
          onDoubleTapped: root.startEditingLife()
        }

        Row {
          visible: root.editingLife
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "BORN"
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          TextField {
            id: bornField
            width: Style.space(70)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "year"
            foreground: root.foreground
            font.family: root.fontFamily
            inputMethodHints: Qt.ImhDigitsOnly

            Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.space(6)
            text: "LIVE TO"
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          TextField {
            id: expectancyField
            width: Style.space(60)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "90"
            foreground: root.foreground
            font.family: root.fontFamily
            inputMethodHints: Qt.ImhDigitsOnly

            Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
          }
        }

        Text {
          textFormat: Text.PlainText
          id: yearLabel
          visible: !root.editingLife
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.today.getFullYear()
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Text {
          textFormat: Text.PlainText
          id: yearPercent
          visible: !root.editingLife
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.yearDonePercent + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          id: yearTrack
          visible: !root.editingLife
          anchors.left: yearLabel.right
          anchors.right: yearPercent.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(3)
          radius: Math.min(height / 2, Style.cornerRadius)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            width: Math.round(parent.width * root.yearDone)
            height: parent.height
            radius: parent.radius
            color: Color.accent

            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }
      }
    }

    // ---- Memento mori. Only here once someone has gone looking and given
    //      an age; the same rail as the year above it, measured against a
    //      nominal lifetime.
    Item {
      visible: root.birthYear > 0
      width: parent.width
      height: visible ? lifeBlock.height : 0

      Item {
        id: lifeBlock
        anchors.horizontalCenter: parent.horizontalCenter
        width: gridColumn.width
        height: Math.max(lifeLabel.implicitHeight, Style.space(10))

        Text {
          textFormat: Text.PlainText
          id: lifeLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "LIFE"
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Text {
          textFormat: Text.PlainText
          id: lifePercent
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.lifeDonePercent + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          anchors.left: lifeLabel.right
          anchors.right: lifePercent.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(3)
          radius: Math.min(height / 2, Style.cornerRadius)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            width: Math.round(parent.width * root.lifeDone)
            height: parent.height
            radius: parent.radius
            color: Color.accent

            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }

        TapHandler {
          enabled: !root.editingLife
          onDoubleTapped: root.startEditingLife()
        }

        MouseArea {
          id: lifeMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton

          PanelToolTip {
            visible: lifeMouse.containsMouse
            text: "Memento Mori · Double-click to edit"
            fontFamily: root.fontFamily
          }
        }
      }
    }

    }
  }
}
