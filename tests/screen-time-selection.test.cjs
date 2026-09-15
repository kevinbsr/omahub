const test = require('node:test')
const assert = require('node:assert/strict')
const model = require('../ScreenTimeModel.js')

test('selects current and historical days without mutating history', () => {
  const today = { total: 90, apps: { editor: 90 } }
  const days = { '2026-09-14': { total: 60, apps: { browser: 60 } } }
  assert.equal(model.dayFor(days, today, '2026-09-15', '2026-09-15'), today)
  assert.equal(model.dayFor(days, today, '2026-09-14', '2026-09-15'), days['2026-09-14'])
  assert.deepEqual(model.dayFor(days, today, '2026-09-13', '2026-09-15'), { total: 0, apps: {} })
})

test('moves calendar keys across month and year boundaries', () => {
  assert.equal(model.shiftKey('2024-02-28', 1), '2024-02-29')
  assert.equal(model.shiftKey('2024-12-31', 1), '2025-01-01')
  assert.equal(model.shiftKey('2025-01-01', -1), '2024-12-31')
})

test('averages only retained completed days', () => {
  const days = {
    '2026-09-14': { total: 60 },
    '2026-09-13': { total: 120 },
    '2026-09-11': { total: 300 },
  }
  assert.equal(model.averagePreviousDays(days, '2026-09-15', 2), 90)
  assert.equal(model.averagePreviousDays(days, '2026-09-15', 4), 160)
})

test('builds sorted activity history with live today data', () => {
  const days = {
    '2026-09-13': { total: 20 },
    '2026-09-14': { total: 0 },
  }
  assert.deepEqual(model.historyRows(days, { total: 30 }, '2026-09-15'), [
    { key: '2026-09-15', ms: 30 },
    { key: '2026-09-13', ms: 20 },
  ])
})

test('describes meaningful deviation from average', () => {
  assert.equal(model.comparisonText(100, 0), 'Building a 7-day baseline')
  assert.match(model.comparisonText(3 * 3600000, 2 * 3600000), /above/)
  assert.match(model.comparisonText(3600000, 2 * 3600000), /below/)
})

test('turns service identifiers into useful app labels', () => {
  assert.equal(model.displayName('com.jeffser.Alpaca'), 'Alpaca')
  assert.equal(model.displayName('web.whatsapp.com'), 'Whatsapp')
  assert.equal(model.displayName('brave-origin'), 'Brave Origin')
  assert.equal(model.displayName('brave-x.com'), 'Brave X')
})
