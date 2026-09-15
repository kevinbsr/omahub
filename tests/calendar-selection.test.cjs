const assert = require('node:assert/strict');
const test = require('node:test');
const model = require('../ClockModel.js');

process.env.TZ = 'America/New_York';
const date = (year, month, day) => new Date(year, month - 1, day, 12);

test('month navigation clamps the selected day in February', () => {
  assert.equal(model.keyForDate(model.shiftCalendarMonth(date(2028, 1, 31), 1)), '2028-02-29');
  assert.equal(model.keyForDate(model.shiftCalendarMonth(date(2027, 1, 31), 1)), '2027-02-28');
  assert.equal(model.keyForDate(model.shiftCalendarMonth(date(2028, 2, 29), 12)), '2029-02-28');
});

test('month navigation crosses the year boundary in either direction', () => {
  assert.equal(model.keyForDate(model.shiftCalendarMonth(date(2026, 12, 31), 1)), '2027-01-31');
  assert.equal(model.keyForDate(model.shiftCalendarMonth(date(2027, 1, 31), -1)), '2026-12-31');
});

test('relative date counts calendar days across DST changes', () => {
  assert.equal(model.calendarDayDistance(date(2026, 3, 7), date(2026, 3, 9)), 2);
  assert.equal(model.calendarDayDistance(date(2026, 10, 31), date(2026, 11, 2)), 2);
  assert.equal(model.calendarDayDistance(date(2026, 3, 9), date(2026, 3, 7)), -2);
  assert.equal(model.calendarDayDistance(date(2026, 9, 15), date(2026, 9, 15)), 0);
});

test('adjacent-month cells retain the full date needed for selection', () => {
  const weeks = model.monthGrid(2026, 8, 1, '2026-09-15');
  assert.equal(weeks.length, 6);
  const first = weeks[0].days[0];
  assert.equal(first.key, '2026-08-31');
  assert.equal(model.keyForDate(new Date(first.year, first.month, first.day, 12)), first.key);
});
