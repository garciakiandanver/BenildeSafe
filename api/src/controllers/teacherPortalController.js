const pool = require('../config/database');
const { buildDtrDays } = require('../services/dtr');

// The teacher's view is read only: the daily time record (DTR) of the students
// of one course and year level, one month at a time. Teachers have no class
// schedule in the system any more, so the list of students comes from the
// course and year level of the students themselves.

const manilaText = (column) =>
  `to_char(${column}, 'YYYY-MM-DD"T"HH24:MI:SS')`;

const MONTH_PATTERN = /^(\d{4})-(0[1-9]|1[0-2])$/;

const currentMonth = () =>
  new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: '2-digit'
  }).format(new Date());

// "2026-11" -> { start: '2026-11-01', end: '2026-12-01' }
const monthRange = (month) => {
  const match = MONTH_PATTERN.exec(month);
  if (!match) return null;
  const year = Number(match[1]);
  const index = Number(match[2]);
  const pad = (value) => String(value).padStart(2, '0');
  const nextYear = index === 12 ? year + 1 : year;
  const nextMonth = index === 12 ? 1 : index + 1;
  return {
    start: `${year}-${pad(index)}-01`,
    end: `${nextYear}-${pad(nextMonth)}-01`
  };
};

const requireTeacher = (req, res) => {
  if (req.user.role?.toLowerCase() !== 'teacher') {
    res.status(403).json({ message: 'This report is available to teachers only.' });
    return false;
  }
  return true;
};

const fullName = (row) =>
  [row.first_name, row.middle_name, row.last_name]
    .map((part) => String(part ?? '').trim())
    .filter(Boolean)
    .join(' ');

// GET /api/teacher/filters
// The courses and year levels that have students, to fill the two pickers.
const getStudentFilters = async (req, res) => {
  try {
    if (!requireTeacher(req, res)) return;
    const result = await pool.query(
      `
      SELECT
        UPPER(BTRIM(s.course)) AS course_code,
        MAX(c.course_name) AS course_name,
        BTRIM(s.year_level) AS year_level
      FROM students s
      LEFT JOIN courses c ON UPPER(c.course_code) = UPPER(BTRIM(s.course))
      WHERE s.course IS NOT NULL AND BTRIM(s.course) <> ''
        AND s.year_level IS NOT NULL AND BTRIM(s.year_level) <> ''
      GROUP BY UPPER(BTRIM(s.course)), BTRIM(s.year_level)
      ORDER BY UPPER(BTRIM(s.course)), BTRIM(s.year_level)
      `
    );

    const courses = new Map();
    for (const row of result.rows) {
      if (!courses.has(row.course_code)) {
        courses.set(row.course_code, {
          course_code: row.course_code,
          course_name: row.course_name ?? row.course_code,
          year_levels: []
        });
      }
      courses.get(row.course_code).year_levels.push(row.year_level);
    }
    return res.json({ courses: [...courses.values()] });
  } catch (error) {
    console.error('Teacher filters error:', error);
    return res.status(500).json({ message: 'Could not load the course list.' });
  }
};

// GET /api/teacher/students-dtr?course=BSIT&year_level=3&month=2026-11
const getStudentsDtr = async (req, res) => {
  try {
    if (!requireTeacher(req, res)) return;

    const course = String(req.query.course ?? '').trim();
    const yearLevel = String(req.query.year_level ?? '').trim();
    const month = String(req.query.month ?? currentMonth()).trim();
    if (!course || !yearLevel) {
      return res.status(400).json({ message: 'Choose a course and a year level.' });
    }
    const range = monthRange(month);
    if (!range) {
      return res.status(400).json({ message: 'The month must look like 2026-11.' });
    }

    const result = await pool.query(
      `
      SELECT
        s.user_id,
        s.student_number,
        s.first_name,
        s.middle_name,
        s.last_name,
        a.attendance_date::text AS date_key,
        ${manilaText('a.time_in')} AS time_in_text,
        ${manilaText('a.time_out')} AS time_out_text,
        a.status
      FROM students s
      LEFT JOIN attendance a
        ON a.user_id = s.user_id
        AND a.time_in IS NOT NULL
        AND a.attendance_date >= $3::date
        AND a.attendance_date < $4::date
      WHERE UPPER(BTRIM(s.course)) = UPPER($1)
        AND UPPER(BTRIM(s.year_level)) = UPPER($2)
      ORDER BY s.last_name, s.first_name, s.user_id, a.time_in
      `,
      [course, yearLevel, range.start, range.end]
    );

    const students = new Map();
    for (const row of result.rows) {
      if (!students.has(row.user_id)) {
        students.set(row.user_id, {
          user_id: row.user_id,
          student_number: row.student_number,
          name: fullName(row),
          records: []
        });
      }
      if (row.date_key) students.get(row.user_id).records.push(row);
    }

    const list = [...students.values()].map(({ records, ...student }) => {
      const days = buildDtrDays(records);
      return {
        ...student,
        days,
        days_on_campus: days.filter((day) => !day.absent).length,
        total_minutes: days.reduce((sum, day) => sum + day.minutes, 0)
      };
    });

    return res.json({ course: course.toUpperCase(), year_level: yearLevel, month, students: list });
  } catch (error) {
    console.error('Teacher students DTR error:', error);
    return res.status(500).json({ message: 'Could not load the student report.' });
  }
};

module.exports = { getStudentFilters, getStudentsDtr };
