import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "WeatherModel.js" as WeatherModel

// The weather data layer, lifted out of omarchy.weather's Panel.qml.
//
// It lives apart from WeatherTab.qml because the bar icon needs a condition
// to show whether or not anyone has opened the weather page — and pages here
// are loaded on first visit. Panel.qml owns one of these and hands it to
// both, so the fetching happens once and the icon is live from startup.
//
// Everything visual is WeatherTab's; everything that talks to the network,
// the location state file, or `omarchy-weather-location` is here. The
// location editing session lives here too, because the fetch callbacks are
// what resolve it — the tab drives it and renders it, but does not own it.
Item {
  id: root

  // The hub panel, for settings (`unit`, `refreshMinutes`).
  property var hub: null

  function setting(name, fallback) {
    return hub && typeof hub.setting === "function" ? hub.setting(name, fallback) : fallback
  }

  // Fired when an edit session ends on its own (saved, or cleared) so the
  // tab can hand keyboard focus back to the panel.
  signal editingFinished()

  // Parsed wttr.in j1 response. Kept on failure so stale data stays visible.
  property var report: null
  property var dailyForecastReport: null
  property string wttrLocation: ""
  property double reportUpdatedAt: 0
  property double dailyUpdatedAt: 0
  property double lastRefreshAttempt: 0
  property bool forecastFailed: false
  property bool dailyFailed: false
  readonly property double updatedAt: current === openMeteoCurrent ? dailyUpdatedAt : reportUpdatedAt
  readonly property bool refreshing: dailyForecastProc.running || (!current && (forecastProc.running || ipLocationProc.running))
  readonly property bool refreshFailed: current === openMeteoCurrent && current ? dailyFailed : (forecastFailed && (dailyFailed || !current))
  readonly property bool searchingLocation: geocodeProc.running || geocodeDebounce.running
  property bool searchCompleted: false
  property string locationError: ""

  // Auto-detected position from the public IP (ipinfo.io), used when no location
  // is configured. Before this, auto-detect depended entirely on wttr.in: it
  // named the area AND supplied the coordinates for the open-meteo forecast, so
  // when wttr.in's TLS certificate expired (2026-09-15) the hub had no weather
  // at all. It is re-read on every refresh, so the weather follows a trip, and
  // it is never saved.
  property var ipLocation: null

  // Configured location, read from the weather.json state file (owned by
  // omarchy-weather-location). The query is the wttr.in path segment
  // (coordinates when stored, else the encoded name); empty means IP
  // auto-detect. The watch makes hand edits take effect live.
  property var configuredLocationState: ({ name: "", latitude: null, longitude: null })
  readonly property string configuredLocation: configuredLocationState.name
  readonly property string locationQuery: WeatherModel.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)

  // A location change invalidates both reports before the next request.
  onLocationQueryChanged: {
    // Never label the previous city's cached weather as the new location.
    report = null
    label = ""
    dailyForecastReport = null
    reportUpdatedAt = 0
    dailyUpdatedAt = 0
    forecastRetryTimer.stop()
    dailyForecastRetryTimer.stop()
    if (savingLocation) savingLocationQueryStarted = true
    forecastRetries = 0
    dailyForecastRetries = 0
    forecastProc.running = false
    dailyForecastProc.running = false
    Qt.callLater(refresh)
  }

  property FileView locationFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.configuredLocationState = WeatherModel.parseLocationFile(text())
    onLoadFailed: root.configuredLocationState = WeatherModel.parseLocationFile("")
  }

  // The first read can race shell startup (observed sporadically), leaving a
  // stored location unhonored until the next file write. One delayed reload
  // self-corrects; if the first read was fine it's a no-op, since identical
  // state doesn't change locationQuery and so triggers no refetch.
  Timer {
    interval: 1500
    running: true
    onTriggered: root.locationFile.reload()
  }

  property int forecastRetries: 0
  property int dailyForecastRetries: 0

  // Click-to-edit state for the location label.
  property bool editingLocation: false
  property bool savingLocation: false
  property bool savingLocationQueryStarted: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

  // The condition glyph. Read by the bar icon as much as by the page, which
  // is the whole reason this object exists outside the page.
  property string label: ""

  // wttr's current conditions when available; open-meteo's (bundled with the
  // much faster daily forecast fetch) fill the hero while wttr is in flight.
  readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
  readonly property var openMeteoCurrent: WeatherModel.openMeteoCurrentCondition(dailyForecastReport)
  readonly property var current: (hasConfiguredCoordinates && openMeteoCurrent) ? openMeteoCurrent : ((report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : openMeteoCurrent)
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  SystemClock { id: forecastClock; precision: SystemClock.Minutes }
  readonly property string forecastDate: WeatherModel.forecastLocalDate(dailyForecastReport, forecastClock.date.getTime(), Qt.formatDate(forecastClock.date, "yyyy-MM-dd"))
  readonly property var todayExtras: WeatherModel.dailyExtras(dailyForecastReport, forecastDate)
  readonly property var forecastDays: WeatherModel.buildForecastDays(report, dailyForecastReport, forecastDate)
  // Country decides metric/imperial when no unit is set. Without a wttr.in
  // report the IP lookup's country code stands in; otherwise the en_US system
  // locale turned Brazil's weather into °F (2026-09-15).
  readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : (ipLocation ? ipLocation.country : "")

  readonly property bool useImperial: WeatherModel.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  readonly property string reportLocation:  configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "") || (ipLocation ? ipLocation.name : "")
  readonly property string reportTempNum:   current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit:        "°" + (useImperial ? "F" : "C")
  readonly property string reportFeels:     current ? formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC) : ""
  readonly property string reportWind:      current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
  readonly property string reportHumidity:  current ? (current.humidity + "%") : ""

  // Every remote body is bounded in bytes as well as in seconds. curl's own
  // --max-filesize only refuses a response that declares its length, so the
  // hard stop is `head -c`: at the cap the pipe closes and curl dies with it.
  // A truncated body fails to parse and takes the existing retry path, which
  // is the intended outcome -- a weather service that answers with a gigabyte
  // is not one to keep in memory while deciding what to do about it.
  //
  // The bash script here is a fixed string; the URL arrives as a positional
  // argument and is never interpolated into it, so a location query keeps
  // being a string rather than becoming shell. --proto '=https' means a
  // redirect cannot walk the fetch down to http or file.
  function fetch(url, seconds, maxBytes) {
    return ["bash", "-c",
      'exec curl -fsS --proto "=https" --max-time "$2" --max-filesize "$3" -- "$1" | head -c "$3"',
      "omahub-weather-fetch", String(url), String(seconds), String(maxBytes)]
  }

  function refresh() {
    lastRefreshAttempt = Date.now()
    forecastFailed = false
    dailyFailed = false
    // Each full refresh cycle gets a fresh retry budget, so an earlier
    // exhausted round (e.g. waking with the network still down) doesn't
    // starve retries for the rest of the session.
    forecastRetries = 0
    dailyForecastRetries = 0
    if (!forecastProc.running) forecastProc.running = true
    if (root.locationQuery === "" && !locationProc.running) locationProc.running = true
    if (!root.hasConfiguredCoordinates && !ipLocationProc.running) ipLocationProc.running = true
    // With stored coordinates this fetches open-meteo right away — no need
    // to wait for the slow wttr response. Without them it's a no-op until
    // wttr reports the detected area.
    refreshDailyForecast(null)
  }

  function refreshDailyForecast(sourceReport) {
    if (dailyForecastProc.running) return

    var lat = parseFloat(String(root.configuredLocationState.latitude))
    var lon = parseFloat(String(root.configuredLocationState.longitude))
    if ((isNaN(lat) || isNaN(lon)) && root.ipLocation) {
      lat = root.ipLocation.latitude
      lon = root.ipLocation.longitude
    }
    if (isNaN(lat) || isNaN(lon)) {
      var area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : root.areaInfo
      if (!area) return
      lat = parseFloat(String(area.latitude || ""))
      lon = parseFloat(String(area.longitude || ""))
    }
    if (isNaN(lat) || isNaN(lon)) return

    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,rain_sum,showers_sum,uv_index_max,sunrise,sunset"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
      + "&forecast_days=4"
      + "&timezone=auto"
    dailyForecastProc.command = root.fetch(url, 5, 262144)
    dailyForecastProc.running = true
  }

  // ---- Location editing. The tab swaps the label for a search field and
  //      renders the suggestions; picking one persists name + coordinates
  //      through omarchy-weather-location. An empty commit returns to auto.
  function startEditingLocation() {
    editingLocation = true
    locationError = ""
    searchCompleted = false
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    suggestionIndex = 0
  }

  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    geocodeDebounce.stop()
    geocodePendingQuery = ""
    locationError = ""
    root.editingFinished()
  }

  function moveSuggestion(delta) {
    var next = suggestionIndex + delta
    if (next < 0 || next >= locationSuggestions.length) return
    suggestionIndex = next
  }

  // Takes the field text rather than reaching for it: the field belongs to
  // the tab, and this object outlives it.
  function commitLocation(text) {
    if (String(text || "").trim() !== "" && (searchingLocation || locationSuggestions.length === 0)) {
      locationError = "Choose a city from the search results."
      return
    }
    var location = WeatherModel.locationCommit(text, locationSuggestions, suggestionIndex)
    if (location.name === "") {
      clearLocation()
      return
    }
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: location.name,
      latitude: location.latitude,
      longitude: location.longitude
    }
    persistLocation(location.name, location.latitude, location.longitude)
  }

  function clearLocation() {
    persistLocation("", null, null)
    wttrLocation = ""
    cancelEditingLocation()
  }

  function pickSuggestion(suggestion) {
    if (!suggestion) return
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: suggestion.name,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude
    }
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
  }

  function finishSavingLocation() {
    if (savingLocation && savingLocationQueryStarted) cancelEditingLocation()
  }

  function persistLocation(name, latitude, longitude) {
    if (name && latitude !== null && longitude !== null)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude]
    else if (name)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }

  // Debounced geocoding. Only one curl runs at a time; if the query moved on
  // while a fetch was in flight, the latest query is fetched right after.
  function requestGeocode(text) {
    var query = String(text || "").trim()
    if (query.length < 2) {
      locationSuggestions = []
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }

  function queueGeocode(text) {
    geocodePendingQuery = String(text || "").trim()
    locationSuggestions = []
    locationError = ""
    searchCompleted = false
    geocodeDebounce.restart()
  }

  function startGeocode() {
    if (!editingLocation || geocodePendingQuery.length < 2 || geocodeProc.running) return
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = root.fetch(
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json",
      5, 65536)
    geocodeProc.running = true
  }

  function formatTemp(value) {
    return WeatherModel.formatTemp(value, useImperial)
  }

  function dayName(dateString) {
    return WeatherModel.dayName(dateString, function(date) { return Qt.formatDate(date, "dddd") })
  }

  // Bare degree value (no unit letter), used in the forecast row.
  function bareTempForDay(day, kind) {
    return WeatherModel.bareTempForDay(day, kind, useImperial)
  }

  // Representative icon for a forecast day: the hourly entry nearest noon.
  function dayIcon(day) {
    return WeatherModel.dayIcon(day)
  }

  Process {
    id: forecastProc
    property string requestedLocation: ""
    onRunningChanged: if (running) requestedLocation = root.locationQuery
    command: root.fetch("https://wttr.in/" + root.locationQuery + "?format=j1", 10, 524288)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (forecastProc.requestedLocation !== root.locationQuery) return
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          if (!parsed.current_condition || !parsed.current_condition[0]) throw new Error("Missing current weather")
          root.report = parsed
          root.reportUpdatedAt = Date.now()
          root.forecastFailed = false
          if (!root.hasConfiguredCoordinates)
            root.label = WeatherModel.provisionalCurrentIcon(parsed.current_condition && parsed.current_condition[0], root.label)
          root.forecastRetries = 0
          if (WeatherModel.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr"))
            root.finishSavingLocation()
          // Stored coordinates already drove the fast open-meteo fetch from
          // refresh(); only auto-detect needs the area wttr reported.
          if (isNaN(parseFloat(String(root.configuredLocationState.latitude))))
            root.refreshDailyForecast(parsed)
        } catch (e) {
          // Keep last-good report visible, but try again shortly.
          root.scheduleForecastRetry()
        }
      }
    }
  }

  // wttr.in can be slow or flaky, especially for a location it hasn't
  // cached yet. Retry a few times before leaving it to the refresh timer.
  function scheduleForecastRetry() {
    forecastFailed = true
    if (forecastRetries >= 3) {
      if (savingLocation && !hasConfiguredCoordinates && !openMeteoCurrent) {
        savingLocation = false
        locationError = "City saved, but weather is unavailable. Try refreshing later."
      }
      return
    }
    forecastRetries++
    forecastRetryTimer.restart()
  }

  Timer {
    id: forecastRetryTimer
    interval: 2500
    onTriggered: if (!forecastProc.running) forecastProc.running = true
  }

  // With configured coordinates this fetch is the only thing that updates the
  // bar icon, so a dropped response (e.g. waking before the network is back)
  // must retry rather than wait out the refresh timer with a stale icon.
  function scheduleDailyForecastRetry() {
    dailyFailed = true
    if (dailyForecastRetries >= 3) {
      if (savingLocation && hasConfiguredCoordinates) {
        savingLocation = false
        locationError = "City saved, but weather is unavailable. Try refreshing later."
      }
      return
    }
    dailyForecastRetries++
    dailyForecastRetryTimer.restart()
  }

  Timer {
    id: dailyForecastRetryTimer
    interval: 2500
    onTriggered: root.refreshDailyForecast(null)
  }

  Process {
    id: dailyForecastProc
    property string requestedLocation: ""
    onRunningChanged: if (running) requestedLocation = root.locationQuery
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (dailyForecastProc.requestedLocation !== root.locationQuery) return
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleDailyForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          var parsedCurrent = WeatherModel.openMeteoCurrentCondition(parsed)
          if (!parsedCurrent || !parsed.daily || !parsed.daily.time) throw new Error("Incomplete forecast")
          root.dailyForecastReport = parsed
          root.dailyUpdatedAt = Date.now()
          root.dailyFailed = false
          root.label = WeatherModel.currentIcon(parsedCurrent, root.label)
          root.dailyForecastRetries = 0
          if (WeatherModel.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "open-meteo"))
            root.finishSavingLocation()
        } catch (e) {
          // Keep last-good daily forecast visible, but try again shortly.
          root.scheduleDailyForecastRetry()
        }
      }
    }
  }

  Process {
    id: geocodeProc
    onExited: if (root.editingLocation && root.geocodePendingQuery !== root.geocodeActiveQuery)
      Qt.callLater(root.startGeocode)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.editingLocation) return
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) return
        try {
          var response = JSON.parse(text)
          if (response.error) throw new Error("Search failed")
          root.locationSuggestions = WeatherModel.parseGeocodingResults(text)
          root.searchCompleted = true
        } catch (error) {
          root.locationSuggestions = []
          root.locationError = "City search failed. Check the connection and try again."
        }
        root.suggestionIndex = 0
      }
    }
  }

  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode(root.geocodePendingQuery)
  }

  Process {
    id: locationSaveProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.savingLocation = false
        root.locationError = "Could not save the city. Try again."
        root.locationFile.reload()
        return
      }
      if (!root.savingLocation) return

      // FileView handles changed locations. Explicitly refresh here too so
      // saving the already-active location cannot strand the spinner.
      root.locationFile.reload()
      if (!root.savingLocationQueryStarted) {
        root.savingLocationQueryStarted = true
        root.forecastRetries = 0
        root.dailyForecastRetries = 0
        forecastProc.running = false
        dailyForecastProc.running = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: locationProc
    command: root.fetch("https://wttr.in/?format=%l", 4, 4096)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        root.wttrLocation = raw.split(",")[0]
      }
    }
  }

  Process {
    id: ipLocationProc
    command: root.fetch("https://ipinfo.io/json", 5, 8192)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var info = JSON.parse(String(text || ""))
          var loc = String(info.loc || "").split(",")
          var lat = parseFloat(loc[0]), lon = parseFloat(loc[1])
          if (isNaN(lat) || isNaN(lon)) return
          var moved = !root.ipLocation
            || Math.abs(root.ipLocation.latitude - lat) > 0.05 || Math.abs(root.ipLocation.longitude - lon) > 0.05
          root.ipLocation = { name: String(info.city || ""), country: String(info.country || ""), latitude: lat, longitude: lon }
          // First fix, or a new place: fetch the forecast for it now instead of
          // waiting for wttr.in to report an area.
          if (moved && !root.hasConfiguredCoordinates) {
            root.dailyForecastRetries = 0
            root.refreshDailyForecast(null)
          }
        } catch (e) {
        }
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
