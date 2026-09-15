const assert = require('node:assert/strict');
const test = require('node:test');
const model = require('../WeatherModel.js');

const report = {utc_offset_seconds: -10800, daily: {
  time: ['2026-09-15', '2026-09-16'],
  temperature_2m_min: [18, 19], temperature_2m_max: [24, 25],
  precipitation_probability_max: [0, 70], rain_sum: [0, 2.3], showers_sum: [0, 0.5],
  uv_index_max: [0, 6.8],
  sunrise: ['2026-09-15T05:48', '2026-09-16T05:47'],
  sunset: ['2026-09-15T17:50', '2026-09-16T17:51']
}};

test('zero is valid weather, while unknown fields remain unknown', () => {
  assert.deepEqual(model.dailyExtras(report, '2026-09-15'), {
    precipProbability: 0, rainMm: 0, uvMax: 0, sunrise: '05:48', sunset: '17:50'
  });
  const empty = model.dailyExtras(null, '2026-09-15');
  assert.equal(empty.precipProbability, null);
  assert.equal(empty.rainMm, null);
  assert.equal(empty.uvMax, null);
  assert.equal(empty.sunrise, '');
  assert.equal(model.dailyValue(null, '%'), '—');
  assert.equal(model.dailyValue(0, '%'), '0%');
});

test('daily dates align extras with forecast rows and sum rain plus showers', () => {
  const rows = model.openMeteoForecastDays(report, '2026-09-15');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].date, '2026-09-16');
  assert.equal(rows[0].extras.precipProbability, 70);
  assert.equal(model.dailyValue(rows[0].extras.rainMm, ' mm', 1), '2.8 mm');
  assert.equal(rows[0].extras.uvMax, 6.8);
  assert.equal(model.dailyExtras(report, '2026-09-17').rainMm, null);
});

test('the city date crosses midnight independently of the desktop timezone', () => {
  const now = Date.parse('2026-09-16T01:00:00Z');
  assert.equal(model.forecastLocalDate(report, now, 'fallback'), '2026-09-15');
  assert.equal(model.forecastLocalDate({utc_offset_seconds: 32400}, now, ''), '2026-09-16');
  assert.equal(model.forecastLocalDate({}, now, 'fallback'), 'fallback');
  assert.equal(model.dailyExtras(report, '2026-09-15').sunrise, '05:48');
});

test('invalid, incomplete and polar-day values do not turn into invented readings', () => {
  const broken = {daily: {time: ['2026-09-15'], precipitation_probability_max: [101],
    rain_sum: [2], uv_index_max: [null], sunrise: [null], sunset: ['2026-09-15T28:00']}};
  const extras = model.dailyExtras(broken, '2026-09-15');
  assert.equal(extras.precipProbability, null);
  assert.equal(extras.rainMm, null);
  assert.equal(extras.uvMax, null);
  assert.equal(extras.sunrise, '');
  assert.equal(extras.sunset, '');
  assert.equal(model.dailyValue(NaN, ' mm', 1), '—');
});
