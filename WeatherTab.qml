import QtQuick
import qs.Commons
import qs.Ui
import "WeatherModel.js" as WeatherModel

Item {
  id: root
  property var hub: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.65)
  readonly property var weather: hub ? hub.weather : null
  readonly property bool keysBlocked: weather ? weather.editingLocation : false
  readonly property var days: weather ? weather.forecastDays : []
  readonly property var todayExtras: weather ? weather.todayExtras : ({})
  implicitHeight: column.implicitHeight

  function refresh() {
    if (!weather) return
    weather.locationFile.reload()
    if (Date.now() - weather.lastRefreshAttempt >= weather.refreshMinutes * 60000) refreshNow()
  }
  function refreshNow() { if (weather && !weather.refreshing) weather.refresh() }
  function toggleUnit() {
    if (weather && hub) hub.persistSettings({unit: weather.useImperial ? "metric" : "imperial"})
  }
  function handleTextKey(text) {
    if (text.toLowerCase() === "r") { refreshNow(); return true }
    if (text.toLowerCase() === "u") { toggleUnit(); return true }
    return false
  }
  function handleActivate() { startEditing(); return true }
  function panelClosed() { if (weather && weather.editingLocation) weather.cancelEditingLocation() }
  function startEditing() {
    if (!weather || weather.editingLocation) return
    weather.startEditingLocation()
    Qt.callLater(function() {
      locationField.text = root.weather.configuredLocation
      root.weather.queueGeocode(locationField.text)
      locationField.selectAll()
      locationField.forceActiveFocus()
      if (root.hub) root.hub.ensureActiveRectVisible(editor.y, editor.height)
    })
  }
  Connections {
    target: root.weather
    function onEditingFinished() { if (root.hub) root.hub.focusKeyCatcher() }
  }

  // Shared geometry keeps labels, values and optional icons aligned across grids.
  component MetricCard: Rectangle {
    required property string label
    required property string value
    property string glyph: ""
    id: metric
    height: Style.space(56)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      Text {
        width: parent.width
        text: metric.label
        elide: Text.ElideRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Item {
        width: parent.width
        height: Math.max(valueLabel.implicitHeight, valueIcon.implicitHeight)
        Text {
          id: valueLabel
          anchors.left: parent.left
          anchors.right: valueIcon.left
          anchors.rightMargin: metric.glyph ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: metric.value
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }
        Text {
          id: valueIcon
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: metric.glyph
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    Item {
      width: parent.width
      height: Style.space(36)
      Text {
        anchors.left: parent.left
        anchors.right: actions.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: root.weather && root.weather.reportLocation ? root.weather.reportLocation : "Choose a city"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.startEditing()
          PanelToolTip { visible: parent.containsMouse; text: "Change city · Enter"; fontFamily: root.fontFamily }
        }
      }
      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        PanelActionButton {
          size: Style.space(32)
          iconText: root.weather ? root.weather.tempUnit : "°C"
          tooltipText: "Switch Celsius / Fahrenheit · U"
          enabled: !!root.weather && !root.keysBlocked
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.body
          onClicked: root.toggleUnit()
        }
        PanelActionButton {
          size: Style.space(32)
          iconText: "↻"
          tooltipText: "Refresh weather · R"
          enabled: !!root.weather && !root.weather.refreshing && !root.keysBlocked
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.refreshNow()
        }
      }
    }

    Column {
      id: editor
      visible: root.keysBlocked
      width: parent.width
      spacing: Style.space(8)
      TextField {
        id: locationField
        width: parent.width
        enabled: root.weather && !root.weather.savingLocation
        placeholderText: "Search city"
        foreground: root.foreground
        font.family: root.fontFamily
        onTextChanged: if (root.weather && root.weather.editingLocation && !root.weather.savingLocation)
          root.weather.queueGeocode(text)
        Keys.onPressed: function(event) {
          if (!root.weather) return
          if (event.key === Qt.Key_Escape) root.weather.cancelEditingLocation()
          else if (event.key === Qt.Key_Down) root.weather.moveSuggestion(1)
          else if (event.key === Qt.Key_Up) root.weather.moveSuggestion(-1)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.weather.commitLocation(text)
          else return
          event.accepted = true
        }
      }
      Text {
        width: parent.width
        text: !root.weather ? "" : root.weather.locationError || (root.weather.savingLocation ? "Saving city and loading weather…"
          : root.weather.searchingLocation ? "Searching cities…"
          : root.weather.searchCompleted && !root.weather.locationSuggestions.length ? "No cities found. Try a nearby city or a different spelling."
          : "Select a city from the results.")
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Repeater {
        model: root.weather && !root.weather.savingLocation ? root.weather.locationSuggestions : []
        Rectangle {
          id: suggestion
          required property var modelData
          required property int index
          readonly property bool selected: root.weather && root.weather.suggestionIndex === index
          width: editor.width
          height: suggestionLabels.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: selected ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
          onSelectedChanged: if (selected && root.hub) Qt.callLater(function() {
            root.hub.ensureActiveRectVisible(editor.y + suggestion.y, suggestion.height)
          })
          Column {
            id: suggestionLabels
            x: Style.space(12)
            y: Style.space(8)
            width: parent.width - Style.space(24)
            spacing: Style.space(3)
            Text { width: parent.width; text: modelData.name; elide: Text.ElideRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            Text { width: parent.width; text: modelData.description; elide: Text.ElideRight; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.weather) root.weather.suggestionIndex = index
            onClicked: if (root.weather) root.weather.pickSuggestion(modelData)
          }
        }
      }
      Row {
        spacing: Style.space(8)
        Button {
          text: "Cancel"
          foreground: root.foreground
          onClicked: if (root.weather) root.weather.cancelEditingLocation()
        }
        Button {
          text: "Use automatic location"
          tooltipText: "Detect an approximate location from your public IP"
          enabled: root.weather && !root.weather.savingLocation
          foreground: root.dim
          onClicked: root.weather.clearLocation()
        }
      }
    }

    Rectangle {
      width: parent.width
      height: Style.space(80)
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
      Column {
        x: Style.space(12)
        y: Style.space(8)
        spacing: Style.space(4)
        Text { text: "CURRENT CONDITIONS"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        Row {
          spacing: Style.space(12)
          Text {
            text: root.weather && root.weather.current ? root.weather.reportTempNum + root.weather.tempUnit : "—"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(44)
            font.weight: Font.Medium
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.weather && root.weather.current ? root.weather.label : "—"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(32)
          }
        }
      }
      Column {
        x: 2 * ((parent.width - Style.space(16)) / 3 + Style.space(8)) + Style.space(12)
        y: Style.space(8)
        width: (parent.width - Style.space(16)) / 3 - Style.space(24)
        spacing: Style.space(6)
        Text { text: "TODAY · PRECIP."; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        Text {
          width: parent.width
          text: WeatherModel.dailyValue(root.todayExtras.precipProbability, "%")
            + " · " + WeatherModel.dailyValue(root.todayExtras.rainMm, " mm", 1)
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    Row {
      visible: root.weather && !!root.weather.current
      width: parent.width
      spacing: Style.space(8)
      Repeater {
        model: [
          {label: "Feels like", value: root.weather ? root.weather.reportFeels : "—"},
          {label: "Wind", value: root.weather ? root.weather.reportWind : "—"},
          {label: "Humidity", value: root.weather ? root.weather.reportHumidity : "—"}
        ]
        MetricCard {
          required property var modelData
          width: (root.width - Style.space(16)) / 3
          label: modelData.label
          value: modelData.value || "—"
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(8)
      PanelSectionHeader {
        width: parent.width
        text: "TODAY · CITY LOCAL TIME"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
      Row {
        width: parent.width
        spacing: Style.space(8)
        Repeater {
          model: [
            {label: "Max UV", value: WeatherModel.dailyValue(root.todayExtras.uvMax, "", 1)},
            {label: "Sunrise", value: root.todayExtras.sunrise || "—"},
            {label: "Sunset", value: root.todayExtras.sunset || "—"}
          ]
          MetricCard {
            required property var modelData
            width: (root.width - Style.space(16)) / 3
            label: modelData.label
            value: modelData.value
          }
        }
      }
    }

    Column {
      visible: root.days.length > 0
      width: parent.width
      spacing: Style.space(8)
      PanelSectionHeader { width: parent.width; text: "NEXT DAYS · LOW / HIGH"; foreground: root.foreground; fontFamily: root.fontFamily }
      Row {
        width: parent.width
        spacing: Style.space(8)
        Repeater {
          model: root.days
          MetricCard {
            required property var modelData
            width: (root.width - Style.space(8) * Math.max(0, root.days.length - 1)) / Math.max(1, root.days.length)
            label: root.weather.dayName(modelData.date)
            value: (root.weather.bareTempForDay(modelData, "min") || "—") + " / " + (root.weather.bareTempForDay(modelData, "max") || "—")
            glyph: root.weather.dayIcon(modelData)
          }
        }
      }
    }
    Text {
      width: parent.width
      text: !root.weather ? "Weather unavailable."
        : root.weather.refreshing ? (root.weather.current ? "Updating weather…" : "Loading weather…")
        : root.weather.refreshFailed ? (root.weather.current ? "Could not update. Showing the last forecast · R to retry." : "Could not load weather. Check the connection · R to retry.")
        : root.weather.updatedAt > 0 ? "Updated " + Qt.formatDateTime(new Date(root.weather.updatedAt), "MMM d, HH:mm")
        : "Waiting for weather · R to retry."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
