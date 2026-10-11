const pool = require('../config/database');

const PERIODS = ['daily', 'weekly', 'monthly'];
const DAY_MS = 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Date / time helpers. Dates are handled as 'YYYY-MM-DD' strings and times as
// 'HH:MM:SS' strings in Philippine time, which is how attendance is stored.
// ---------------------------------------------------------------------------

const manilaToday = () =>
  new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(new Date());

const manilaNowTime = () =>
  new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Manila',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23'
  }).format(new Date());

const parseDate = (text) => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null;
  const date = new Date(`${text}T00:00:00Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== text) {
    return null;
  }
  return date;
};

const formatDate = (date) => date.toISOString().slice(0, 10);
const addDays = (date, days) => new Date(date.getTime() + days * DAY_MS);

// daily = that day, weekly = Monday to Sunday, monthly = whole calendar month.
const getRange = (period, anchor) => {
  if (period === 'daily') return [anchor, anchor];
  if (period === 'weekly') {
    const daysSinceMonday = (anchor.getUTCDay() + 6) % 7;
    const monday = addDays(anchor, -daysSinceMonday);
    return [monday, addDays(monday, 6)];
  }
  const year = anchor.getUTCFullYear();
  const month = anchor.getUTCMonth();
  return [
    new Date(Date.UTC(year, month, 1)),
    new Date(Date.UTC(year, month + 1, 0))
  ];
};

// ---------------------------------------------------------------------------
// Status of one student for one class meeting.
//
// A check-in session "covers" the class if the student arrived before the class
// ended and had not already checked out before it started. The covering session
// that started first decides the result: present if the student arrived by the
// class's late cutoff, otherwise late. No covering session means absent, unless
// the class has not finished yet (upcoming / pending).
// ---------------------------------------------------------------------------
const classifyMeeting = ({ meeting, date, sessions, today, nowTime }) => {
  const lateAfter = meeting.late_after || meeting.start_time;
  const covering = sessions.filter(
    (session) =>
      session.time_in < meeting.end_time &&
      (!session.time_out || session.time_out > meeting.start_time)
  );

  if (covering.length > 0) {
    const first = covering[0]; // sessions arrive ordered by time_in
    return {
      status: first.time_in > lateAfter ? 'late' : 'present',
      time_in: first.time_in,
      time_out: first.time_out
    };
  }

  const none = { time_in: null, time_out: null };
  if (date > today) return { status: 'upcoming', ...none };
  if (date === today && nowTime < meeting.end_time) {
    return {
      status: nowTime < meeting.start_time ? 'upcoming' : 'pending',
      ...none
    };
  }
  return { status: 'absent', ...none };
};

// GET /api/teacher/class-attendance?schedule_id=...&period=daily|weekly|monthly&date=YYYY-MM-DD
// Attendance of every student in one of the logged-in teacher's classes.
const getClassAttendance = async (req, res) => {
  try {
    if (req.user.role?.toLowerCase() !== 'teacher') {
      return res.status(403).json({
        message: 'The class attendance portal is available to teachers only.'
      });
    }

    const scheduleId = String(req.query.schedule_id ?? '').trim();
    if (!scheduleId) {
      return res.status(400).json({ message: 'Choose a class first.' });
    }

    const period = String(req.query.period ?? 'weekly').trim().toLowerCase();
    if (!PERIODS.includes(period)) {
      return res.status(400).json({
        message: 'Period must be daily, weekly, or monthly.'
      });
    }

    const today = manilaToday();
    const anchor = parseDate(String(req.query.date ?? today).trim());
    if (!anchor) {
      return res.status(400).json({
        message: 'Date must be in YYYY-MM-DD format.'
      });
    }
    const [rangeStart, rangeEnd] = getRange(period, anchor);
    const startDate = formatDate(rangeStart);
    const endDate = formatDate(rangeEnd);

    // 1. The selected schedule row must belong to this teacher.
    const selected = await pool.query(
      `
      SELECT cs.id, cs.course, cs.year_level, cs.section, cs.subject,
             cs.academic_term_id
      FROM class_schedules cs
      WHERE cs.id = $1 AND cs.teacher_user_id = $2 AND NOT cs.is_archived
      `,
      [scheduleId, req.user.userId]
    );
    if (selected.rowCount === 0) {
      return res.status(404).json({ message: 'Class not found.' });
    }
    const cls = selected.rows[0];

    // 2. Every weekly meeting of that class (same course, year, section, subject).
    const meetingsResult = await pool.query(
      `
      SELECT cs.id, cs.weekday, cs.start_time, cs.late_after, cs.end_time
      FROM class_schedules cs
      WHERE cs.teacher_user_id = $1
        AND cs.academic_term_id = $2
        AND NOT cs.is_archived
        AND UPPER(BTRIM(cs.course)) = UPPER(BTRIM($3))
        AND UPPER(BTRIM(cs.year_level)) = UPPER(BTRIM($4))
        AND COALESCE(UPPER(BTRIM(cs.section)), '') =
            COALESCE(UPPER(BTRIM($5)), '')
        AND UPPER(BTRIM(cs.subject)) = UPPER(BTRIM($6))
      ORDER BY cs.weekday, cs.start_time
      `,
      [
        req.user.userId,
        cls.academic_term_id,
        cls.course,
        cls.year_level,
        cls.section,
        cls.subject
      ]
    );
    const meetings = meetingsResult.rows;

    // 3. The class dates inside the chosen range.
    const classSessions = [];
    for (
      let day = rangeStart;
      day.getTime() <= rangeEnd.getTime();
      day = addDays(day, 1)
    ) {
      for (const meeting of meetings) {
        if (meeting.weekday === day.getUTCDay()) {
          classSessions.push({
            date: formatDate(day),
            weekday: meeting.weekday,
            start_time: meeting.start_time,
            late_after: meeting.late_after,
            end_time: meeting.end_time
          });
        }
      }
    }

    // 4. Students of the class. A blank section on the schedule means the
    //    class is for every section of that course and year level.
    const studentsResult = await pool.query(
      `
      SELECT s.id, s.user_id, s.student_number,
             s.first_name, s.middle_name, s.last_name
      FROM students s
      WHERE UPPER(BTRIM(s.course)) = UPPER(BTRIM($1))
        AND UPPER(BTRIM(s.year_level)) = UPPER(BTRIM($2))
        AND (
          COALESCE(BTRIM($3), '') = ''
          OR UPPER(BTRIM(s.section)) = UPPER(BTRIM($3))
        )
      ORDER BY s.last_name, s.first_name
      `,
      [cls.course, cls.year_level, cls.section]
    );
    const students = studentsResult.rows;

    // 5. Their check-in sessions inside the range (Philippine local times).
    const sessionsByStudent = new Map();
    const userIds = students.map((student) => student.user_id).filter(Boolean);
    if (userIds.length > 0 && classSessions.length > 0) {
      const attendanceResult = await pool.query(
        `
        SELECT
          a.user_id,
          a.attendance_date::text AS date,
          to_char(a.time_in, 'HH24:MI:SS') AS time_in,
          to_char(a.time_out, 'HH24:MI:SS') AS time_out
        FROM attendance a
        WHERE a.user_id = ANY($1::uuid[])
          AND a.attendance_date BETWEEN $2::date AND $3::date
          AND a.time_in IS NOT NULL
          AND LOWER(COALESCE(a.status, '')) <> 'absent'
        ORDER BY a.user_id, a.attendance_date, a.time_in
        `,
        [userIds, startDate, endDate]
      );
      for (const row of attendanceResult.rows) {
        if (!sessionsByStudent.has(row.user_id)) {
          sessionsByStudent.set(row.user_id, new Map());
        }
        const byDate = sessionsByStudent.get(row.user_id);
        if (!byDate.has(row.date)) byDate.set(row.date, []);
        byDate.get(row.date).push({
          time_in: row.time_in,
          time_out: row.time_out
        });
      }
    }

    // 6. Work out every student's status for every class meeting.
    const nowTime = manilaNowTime();
    const totals = { present: 0, late: 0, absent: 0 };
    const studentRows = students.map((student) => {
      const byDate = sessionsByStudent.get(student.user_id) ?? new Map();
      const summary = { present: 0, late: 0, absent: 0 };
      const attendance = classSessions.map((session) => {
        const result = classifyMeeting({
          meeting: session,
          date: session.date,
          sessions: byDate.get(session.date) ?? [],
          today,
          nowTime
        });
        if (summary[result.status] !== undefined) {
          summary[result.status] += 1;
          totals[result.status] += 1;
        }
        return {
          date: session.date,
          start_time: session.start_time,
          end_time: session.end_time,
          ...result
        };
      });

      const initial = student.middle_name
        ? ` ${String(student.middle_name).trim().charAt(0)}.`
        : '';
      return {
        student_id: student.id,
        student_number: student.student_number,
        name: `${student.last_name}, ${student.first_name}${initial}`,
        summary,
        attendance
      };
    });

    return res.json({
      class: {
        schedule_id: cls.id,
        subject: cls.subject,
        course: cls.course,
        year_level: cls.year_level,
        section: cls.section,
        meetings: meetings.map((meeting) => ({
          id: meeting.id,
          weekday: meeting.weekday,
          start_time: meeting.start_time,
          late_after: meeting.late_after,
          end_time: meeting.end_time
        }))
      },
      period,
      start_date: startDate,
      end_date: endDate,
      today,
      sessions: classSessions,
      totals,
      students: studentRows
    });
  } catch (error) {
    console.error('Get class attendance error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The class ID is invalid.' });
    }
    return res.status(500).json({
      message: 'Could not load the class attendance.'
    });
  }
};

module.exports = {
  getClassAttendance
};