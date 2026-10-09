// Beispieldaten für ?demo=1: die aktuelle Woche und die vier Wochen davor (Werkstudent, 20 h an 2 Tagen).

import { DayType, createEntry, parseTime, plusDays, weekStartOf } from './core.js';

function work(date, start, end, manualBreakMinutes = 0) {
  const fields = { start: parseTime(start), manualBreakMinutes };
  if (end) fields.end = parseTime(end);
  return createEntry(date, fields);
}

/** Einträge bis einschließlich [today]; heute ist nur der Beginn gestempelt. */
export function demoEntries(today) {
  const week = weekStartOf(today);
  const day = (offset) => plusDays(week, offset);
  const entries = [
    work(day(-25), '08:00', '18:00', 60),
    work(day(-24), '08:00', '17:00'),
    createEntry(day(-20), { type: DayType.VACATION }),
    work(day(-17), '09:00', '19:45'),
    createEntry(day(-14), { type: DayType.SICK }),
    work(day(-12), '08:00', '18:45'),
    work(day(-6), '08:00', '18:00'),
    work(day(-4), '07:30', '18:30'), // mehr als 10 h
  ];
  if (today !== week) entries.push(work(week, '08:00', '18:45'));
  entries.push(work(today, '08:15', null));
  const result = {};
  for (const entry of entries) result[entry.date] = entry;
  return result;
}
