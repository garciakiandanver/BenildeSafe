// Daily time record (DTR).
//
// A student can time in and out several times in one day (the app times them in
// when they are inside the campus and out when they leave). The DTR joins those
// records into one row per day:
//   first_in      the first time in of the day
//   last_out      the last time out of the day (null while still inside)
//   minutes       the minutes on campus: the sum of every time in to time out,
//                 so the time spent outside between two visits is not counted
//   sessions      every time in and time out of that day, in order
//
// Times are Manila wall-clock text such as "2026-11-04T08:05:00" (see
// attendanceController), so they are compared as UTC numbers and never touch the
// time zone of the server.

const toMs = (text) => (text ? Date.parse(`${text}Z`) : NaN);

const manilaNowText = () => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23'
  }).formatToParts(new Date());
  const get = (type) => parts.find((part) => part.type === type)?.value;
  return `${get('year')}-${get('month')}-${get('day')}T${get('hour')}:${get('minute')}:${get('second')}`;
};

// records: [{ date_key: 'YYYY-MM-DD', time_in_text, time_out_text, status }]
// in any order. Returns one entry per day, oldest day first.
const buildDtrDays = (records, nowText = manilaNowText()) => {
  const today = nowText.slice(0, 10);
  const byDate = new Map();

  for (const record of records) {
    if (!record.date_key || !record.time_in_text) continue;
    if (!byDate.has(record.date_key)) byDate.set(record.date_key, []);
    byDate.get(record.date_key).push(record);
  }

  const days = [];
  for (const [date, list] of byDate) {
    list.sort((a, b) => toMs(a.time_in_text) - toMs(b.time_in_text));

    let minutes = 0;
    const sessions = list.map((record) => {
      const absent = String(record.status ?? '').toLowerCase() === 'absent';
      const start = toMs(record.time_in_text);
      // A session that is still open counts until now, but only today. An old
      // record with no time out has no known end, so it adds nothing.
      const end = record.time_out_text
        ? toMs(record.time_out_text)
        : date === today
          ? toMs(nowText)
          : NaN;
      if (!absent && Number.isFinite(start) && Number.isFinite(end) && end > start) {
        minutes += Math.round((end - start) / 60000);
      }
      return {
        time_in: record.time_in_text,
        time_out: record.time_out_text ?? null,
        status: record.status ?? null
      };
    });

    const allAbsent = sessions.every(
      (session) => String(session.status ?? '').toLowerCase() === 'absent'
    );
    const lastSession = sessions[sessions.length - 1];
    days.push({
      date,
      first_in: sessions[0].time_in,
      last_out: lastSession.time_out,
      minutes: allAbsent ? 0 : minutes,
      absent: allAbsent,
      sessions
    });
  }

  days.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  return days;
};

module.exports = { buildDtrDays, manilaNowText };
