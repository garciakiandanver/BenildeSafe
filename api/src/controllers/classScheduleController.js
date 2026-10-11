const ExcelJS = require('exceljs');
const pool = require('../config/database');

const columns = [
  'course',
  'year_level',
  'section',
  'subject',
  'weekday',
  'start_time',
  'late_after',
  'end_time',
  'teacher_email',
  'campus_code'
];

const weekdays = new Map([
  ['sunday', 0], ['sun', 0], ['monday', 1], ['mon', 1],
  ['tuesday', 2], ['tue', 2], ['wednesday', 3], ['wed', 3],
  ['thursday', 4], ['thu', 4], ['friday', 5], ['fri', 5],
  ['saturday', 6], ['sat', 6]
]);

const normalizeTime = (value) => {
  const text = String(value ?? '').trim();
  let match = text.match(/^(\d{1,2}):([0-5]\d)(?::([0-5]\d))?$/);
  if (match) {
    const hour = Number(match[1]);
    if (hour > 23) return null;
    return `${String(hour).padStart(2, '0')}:${match[2]}:${match[3] ?? '00'}`;
  }

  match = text.match(/^(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(AM|PM|NN)$/i);
  if (!match) return null;
  let hour = Number(match[1]);
  const meridiem = match[3].toUpperCase();
  if (meridiem === 'NN') {
    if (hour !== 12) return null;
  } else {
    hour %= 12;
    if (meridiem === 'PM') hour += 12;
  }
  return `${String(hour).padStart(2, '0')}:${match[2] ?? '00'}:00`;
};

const addMinutes = (time, minutes) => {
  const [hours, mins] = time.split(':').map(Number);
  const totalMinutes = hours * 60 + mins + minutes;
  return `${String(Math.floor(totalMinutes / 60) % 24).padStart(2, '0')}:${String(totalMinutes % 60).padStart(2, '0')}:00`;
};

const parseDelimitedLine = (line, delimiter) => {
  const values = [];
  let value = '';
  let quoted = false;
  for (let i = 0; i < line.length; i += 1) {
    const character = line[i];
    if (character === '"' && quoted && line[i + 1] === '"') {
      value += '"';
      i += 1;
    } else if (character === '"') {
      quoted = !quoted;
    } else if (character === delimiter && !quoted) {
      values.push(value);
      value = '';
    } else {
      value += character;
    }
  }
  if (quoted) throw new Error('CSV file has an unterminated quoted field.');
  values.push(value);
  return values;
};

const detectDelimiter = (line) => {
  const candidates = [',', ';', '\t'];
  return candidates
    .map((delimiter) => ({
      delimiter,
      columns: parseDelimitedLine(line, delimiter).length
    }))
    .sort((left, right) => right.columns - left.columns)[0].delimiter;
};

const parseWeekday = (value) => {
  const text = String(value ?? '').trim().toLowerCase();
  if (/^[0-6]$/.test(text)) return Number(text);
  return weekdays.get(text);
};

const parseSourceTimetable = (
  rows,
  lateAfterMinutes,
  courseCode,
  defaultCampusCode
) => {
  const sourceHeaders = rows.some((row) =>
    String(row[0] ?? '').trim().toLowerCase() === 'code' &&
    String(row[1] ?? '').trim().toLowerCase() === 'subject description'
  );
  if (!sourceHeaders) return null;
  if (!courseCode) {
    throw new Error(
      'Original year-by-year timetables cover a single course. Open the course ' +
      'and upload it there, or use the template with a course column.'
    );
  }

  const yearLevels = new Map([
    ['1st year', '1'], ['first year', '1'],
    ['2nd year', '2'], ['second year', '2'],
    ['3rd year', '3'], ['third year', '3'],
    ['4th year', '4'], ['fourth year', '4']
  ]);
  const normalizedRows = [[...columns, 'teacher_name']];
  let yearLevel;

  for (const row of rows) {
    const first = String(row[0] ?? '').trim();
    const second = String(row[1] ?? '').trim();
    const year = yearLevels.get(first.toLowerCase());
    if (year) {
      yearLevel = year;
      continue;
    }
    if (first.toLowerCase() === 'code') continue;
    if (!yearLevel || !first || /^total\s+units$/i.test(second)) continue;

    const subject = second;
    const weekday = String(row[5] ?? '').trim();
    const timeRange = String(row[6] ?? '').trim();
    const instructorName = String(row[8] ?? '').trim();
    if (!subject || /^(tba|tbd)$/i.test(weekday) || /^(tba|tbd)$/i.test(timeRange)) {
      continue;
    }

    const times = timeRange.match(
      /^\s*(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(AM|PM|NN)\s*[-–]\s*(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(AM|PM|NN)\s*$/i
    );
    const startTime = times
      ? normalizeTime(`${times[1]}${times[2] ? `:${times[2]}` : ''} ${times[3]}`)
      : null;
    const endTime = times
      ? normalizeTime(`${times[4]}${times[5] ? `:${times[5]}` : ''} ${times[6]}`)
      : null;
    if (!startTime || !endTime) {
      throw new Error(`Could not read the time range "${timeRange}" for ${subject}.`);
    }
    const lateAfter = addMinutes(startTime, lateAfterMinutes);
    if (lateAfter >= endTime) {
      throw new Error(
        `The ${lateAfterMinutes}-minute late cutoff reaches the end of ${subject}.`
      );
    }

    normalizedRows.push([
      courseCode,
      yearLevel,
      '',
      subject,
      weekday,
      startTime,
      lateAfter,
      endTime,
      '',
      defaultCampusCode,
      instructorName
    ]);
  }

  if (normalizedRows.length === 1) {
    throw new Error('No scheduled class rows were found in this timetable CSV.');
  }
  return normalizedRows;
};

const parseRows = (rows, courseCode, defaultCampusCode = '') => {
  if (rows.length < 2) {
    throw new Error('The schedule file must contain a header and at least one schedule row.');
  }

  const headers = rows[0].map((value) => String(value ?? '')
    .replace(/[\uFEFF\u200B\u00A0]/g, '')
    .trim()
    .toLowerCase());
  const hasTeacherName = headers.includes('teacher_name') || headers.includes('instructor');
  const missing = columns.filter((column) =>
    column !== 'teacher_email' &&
    column !== 'campus_code' &&
    !headers.includes(column)
  );
  if (!headers.includes('teacher_email') && !hasTeacherName) {
    missing.push('teacher_email or teacher_name/instructor');
  }
  if (missing.length > 0) {
    throw new Error(
      `The uploaded file is missing these timetable headers: ${missing.join(', ')}. ` +
      `Headers detected: ${headers.filter(Boolean).join(', ') || '(none)'}. ` +
      'Select the CSV draft directly, or make sure the first row of your file contains the template headers.'
    );
  }

  const indexes = Object.fromEntries(
    columns.map((column) => [column, headers.indexOf(column)])
  );
  const uploadedCourseIndex = headers.indexOf('course');
  const selectedCourse = String(courseCode ?? '').trim().toUpperCase();
  const teacherNameIndex = headers.includes('teacher_name')
    ? headers.indexOf('teacher_name')
    : headers.indexOf('instructor');

  return rows.slice(1)
    .map((row, index) => ({ row, index }))
    .filter(({ row }) =>
      row.some((value) => String(value ?? '').trim() !== '')
    )
    .map(({ row, index }) => {
      const get = (column) => String(row[indexes[column]] ?? '').trim();
      const uploadedCourse = uploadedCourseIndex < 0
        ? ''
        : String(row[uploadedCourseIndex] ?? '').trim().toUpperCase();
      const rowCourse = selectedCourse || uploadedCourse;
      const entry = {
        rowNumber: index + 2,
        course: rowCourse,
        yearLevel: get('year_level').toUpperCase(),
        section: /^null$/i.test(get('section'))
          ? ''
          : get('section').toUpperCase(),
        subject: get('subject').toUpperCase(),
        weekday: parseWeekday(get('weekday')),
        startTime: normalizeTime(get('start_time')),
        lateAfter: normalizeTime(get('late_after')),
        endTime: normalizeTime(get('end_time')),
        teacherEmail: get('teacher_email').toLowerCase(),
        campusCode: (get('campus_code') || defaultCampusCode)
          .trim()
          .toUpperCase(),
        instructorName: String(row[teacherNameIndex] ?? '').trim()
      };
      const invalidFields = ['course', 'yearLevel', 'subject']
        .filter((field) => !entry[field]);
      if (selectedCourse && uploadedCourse && uploadedCourse !== selectedCourse) {
        entry.error =
          `Row ${entry.rowNumber}: course "${uploadedCourse}" does not match the selected course "${selectedCourse}".`;
      }
      if (!entry.teacherEmail && !entry.instructorName) {
        invalidFields.push('teacher_email or instructor');
      }
      if (!entry.campusCode) invalidFields.push('campus_code');
      if (
        entry.weekday === undefined ||
        !entry.startTime ||
        !entry.lateAfter ||
        !entry.endTime
      ) {
        if (entry.weekday === undefined) invalidFields.push('weekday');
        if (!entry.startTime) invalidFields.push('start_time');
        if (!entry.lateAfter) invalidFields.push('late_after');
        if (!entry.endTime) invalidFields.push('end_time');
      }
      if (!entry.error && invalidFields.length > 0) {
        entry.error = `Row ${entry.rowNumber}: missing or invalid ${invalidFields.join(', ')}.`;
      } else if (!entry.error && (
        entry.startTime >= entry.lateAfter ||
        entry.lateAfter >= entry.endTime
      )) {
        entry.error = `Row ${entry.rowNumber}: times must be ordered start_time < late_after < end_time.`;
      }
      return entry;
    });
};

const readScheduleRows = async (
  file,
  { lateAfterMinutes = 30, courseCode = '', defaultCampusCode = '' } = {}
) => {
  const extension = file.originalname.split('.').pop()?.toLowerCase();
  if (extension === 'csv') {
    const isUtf16 = file.buffer[0] === 0xFF && file.buffer[1] === 0xFE;
    const text = file.buffer
      .toString(isUtf16 ? 'utf16le' : 'utf8')
      .replace(/^\uFEFF/, '')
      .replace(/\u0000/g, '');
    const lines = text.split(/\r?\n/).filter((line) => line.trim());
    if (lines.length === 0) return [];
    const delimiter = detectDelimiter(lines[0]);
    const rows = lines.map((line) => parseDelimitedLine(line, delimiter));
    return parseSourceTimetable(
      rows,
      lateAfterMinutes,
      courseCode,
      defaultCampusCode
    ) ?? rows;
  }

  if (extension !== 'xlsx') {
    throw new Error('Upload a CSV or Excel (.xlsx) file.');
  }

  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(file.buffer);
  const sheet = workbook.worksheets[0];
  if (!sheet) throw new Error('The Excel file contains no worksheet.');

  const rows = [];
  sheet.eachRow({ includeEmpty: false }, (row) => {
    rows.push(row.values.slice(1).map((_, index) => {
      const cell = row.getCell(index + 1);
      if (cell.value instanceof Date) {
        return `${String(cell.value.getUTCHours()).padStart(2, '0')}:${String(cell.value.getUTCMinutes()).padStart(2, '0')}`;
      }
      return cell.text || cell.value || '';
    }));
  });
  return rows;
};

const findActiveTeacher = async (client, email, instructorName) => {
  const result = await client.query(
    `
    SELECT u.id
    FROM users u
    JOIN teachers t ON t.user_id = u.id
    JOIN user_roles ur ON ur.user_id = u.id
    JOIN roles r ON r.id = ur.role_id
    WHERE LOWER(u.email) = $1
      AND LOWER(r.name) = 'teacher'
      AND u.status = 'active'
      AND $1 <> ''
    UNION
    SELECT u.id
    FROM users u
    JOIN teachers t ON t.user_id = u.id
    JOIN user_roles ur ON ur.user_id = u.id
    JOIN roles r ON r.id = ur.role_id
    WHERE LOWER(TRIM(CONCAT_WS(' ', t.first_name, t.middle_name, t.last_name))) = $2
      AND LOWER(r.name) = 'teacher'
      AND u.status = 'active'
      AND $2 <> ''
    LIMIT 1
    `,
    [
      email.toLowerCase(),
      instructorName
        .replace(/^(mr|mrs|ms|miss|dr)\.?\s+/i, '')
        .replace(/\s+/g, ' ')
        .trim()
        .toLowerCase()
    ]
  );
  return result.rows[0]?.id ?? null;
};

const getClassSchedules = async (req, res) => {
  try {
    const courseCode = String(
      req.params.courseCode ?? req.query.courseCode ?? ''
    ).trim().toUpperCase();
    const termId = String(req.query.termId ?? '') || null;
    const result = await pool.query(
      `
      SELECT
        cs.id,
        cs.course,
        cs.year_level,
        cs.section,
        cs.subject,
        cs.weekday,
        cs.start_time,
        cs.late_after,
        cs.end_time,
        cs.is_archived,
        cs.academic_term_id,
        cs.campus_id,
        c.campus_code,
        c.campus_name,
        u.email AS teacher_email,
        COALESCE(
          NULLIF(cs.instructor_name, ''),
          NULLIF(TRIM(CONCAT_WS(' ', t.first_name, t.last_name)), '')
        ) AS teacher_name
      FROM class_schedules cs
      LEFT JOIN campuses c ON c.id = cs.campus_id
      LEFT JOIN teachers t ON t.user_id = cs.teacher_user_id
      LEFT JOIN users u ON u.id = cs.teacher_user_id
      JOIN academic_terms at ON at.id = cs.academic_term_id
      WHERE ($1 = '' OR UPPER(cs.course) = $1)
        AND cs.academic_term_id = COALESCE(
          $2::uuid,
          (SELECT id FROM academic_terms WHERE is_current = TRUE)
        )
        AND NOT cs.is_archived
      ORDER BY cs.course, cs.year_level, cs.section, cs.weekday, cs.start_time
      `,
      [courseCode, termId]
    );
    return res.json({ schedules: result.rows });
  } catch (error) {
    console.error('Get class schedules error:', error);
    return res.status(500).json({
      message: error.code === '42703' && error.column === 'campus_id'
        ? 'The database is missing schedule campus support. Apply migration 008_add_schedule_campuses.sql, then restart the API.'
        : 'Could not load class schedules.'
    });
  }
};

const getAcademicTerms = async (req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        at.id,
        at.school_year,
        at.semester,
        at.is_current,
        COUNT(cs.id) FILTER (WHERE NOT cs.is_archived)::int AS schedule_count
      FROM academic_terms at
      LEFT JOIN class_schedules cs ON cs.academic_term_id = at.id
      GROUP BY at.id
      ORDER BY at.is_current DESC, at.created_at DESC
      `
    );
    return res.json({ terms: result.rows });
  } catch (error) {
    console.error('Get academic terms error:', error);
    return res.status(500).json({ message: 'Could not load academic terms.' });
  }
};

const createAcademicTerm = async (req, res) => {
  const schoolYear = String(req.body.school_year ?? '').trim();
  const semester = String(req.body.semester ?? '').trim();
  if (!schoolYear || !semester) {
    return res.status(400).json({
      message: 'School year and semester are required.'
    });
  }
  if (schoolYear.length > 30 || semester.length > 40) {
    return res.status(400).json({
      message: 'School year must be at most 30 characters and semester at most 40 characters.'
    });
  }

  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    await client.query(
      'UPDATE academic_terms SET is_current = FALSE WHERE is_current = TRUE'
    );
    const result = await client.query(
      `
      INSERT INTO academic_terms (school_year, semester, is_current)
      VALUES ($1, $2, TRUE)
      ON CONFLICT (school_year, semester) DO NOTHING
      RETURNING id, school_year, semester, is_current
      `,
      [schoolYear, semester]
    );
    if (result.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        message: `${schoolYear} ${semester} already exists. Select it from the academic term list instead.`
      });
    }
    await client.query('COMMIT');
    return res.status(201).json({
      message: 'New academic term is now active. Previous semester schedules and attendance have been preserved.',
      term: result.rows[0]
    });
  } catch (error) {
    if (client) await client.query('ROLLBACK').catch(() => {});
    console.error('Create academic term error:', error);
    return res.status(500).json({ message: 'Could not change the academic term.' });
  } finally {
    client?.release();
  }
};

const updateAcademicTerm = async (req, res) => {
  const termId = String(req.params.termId ?? '');
  const schoolYear = String(req.body.school_year ?? '').trim();
  const semester = String(req.body.semester ?? '').trim();
  if (!schoolYear || !semester) {
    return res.status(400).json({
      message: 'School year and semester are required.'
    });
  }
  if (schoolYear.length > 30 || semester.length > 40) {
    return res.status(400).json({
      message: 'School year must be at most 30 characters and semester at most 40 characters.'
    });
  }

  try {
    const result = await pool.query(
      `
      UPDATE academic_terms
      SET school_year = $2, semester = $3
      WHERE id = $1::uuid
      RETURNING id, school_year, semester, is_current
      `,
      [termId, schoolYear, semester]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Academic term not found.' });
    }
    return res.json({
      message: 'Academic term label updated. Its schedules and attendance history were preserved.',
      term: result.rows[0]
    });
  } catch (error) {
    console.error('Update academic term error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The academic term ID is invalid.' });
    }
    if (error.code === '23505') {
      return res.status(409).json({
        message: 'A term with that school year and semester already exists.'
      });
    }
    return res.status(500).json({ message: 'Could not update the academic term.' });
  }
};

const getCourses = async (req, res) => {
  try {
    const termId = String(req.query.termId ?? '') || null;
    const result = await pool.query(
      `
      SELECT
        c.course_code,
        c.course_name,
        c.department_id,
        d.department_code,
        d.department_name,
        COUNT(cs.id)::int AS schedule_count
      FROM courses c
      LEFT JOIN departments d ON d.id = c.department_id
      LEFT JOIN class_schedules cs
        ON UPPER(cs.course) = UPPER(c.course_code)
        AND NOT cs.is_archived
        AND cs.academic_term_id = COALESCE(
          $1::uuid,
          (SELECT id FROM academic_terms WHERE is_current = TRUE)
        )
      GROUP BY
        c.course_code, c.course_name, c.department_id,
        d.department_code, d.department_name
      ORDER BY d.department_name NULLS LAST, c.course_name, c.course_code
      `,
      [termId]
    );
    return res.json({ courses: result.rows });
  } catch (error) {
    console.error('Get courses error:', error);
    if (error.code === '42P01' || error.code === '42703') {
      return res.status(500).json({ message: DEPARTMENTS_SETUP_MESSAGE });
    }
    return res.status(500).json({ message: 'Could not load courses.' });
  }
};

const addCourse = async (req, res) => {
  const courseCode = String(req.body.course_code ?? '').trim().toUpperCase();
  const courseName = String(req.body.course_name ?? '').trim();
  const departmentId = String(req.body.department_id ?? '').trim() || null;
  if (!courseCode || !courseName) {
    return res.status(400).json({
      message: 'Course code and course name are required.'
    });
  }
  if (courseCode.length > 30 || courseName.length > 120) {
    return res.status(400).json({
      message: 'Course code must be at most 30 characters and course name at most 120 characters.'
    });
  }

  try {
    const result = await pool.query(
      `
      INSERT INTO courses (course_code, course_name, department_id)
      VALUES ($1, $2, $3::uuid)
      ON CONFLICT (course_code) DO NOTHING
      RETURNING course_code, course_name, department_id
      `,
      [courseCode, courseName, departmentId]
    );
    if (result.rowCount === 0) {
      return res.status(409).json({
        message: `Course code "${courseCode}" already exists.`
      });
    }
    return res.status(201).json({
      message: 'Course added.',
      course: result.rows[0]
    });
  } catch (error) {
    console.error('Add course error:', error);
    if (error.code === '22P02' || error.code === '23503') {
      return res.status(400).json({ message: 'Choose a valid department.' });
    }
    if (error.code === '42P01' || error.code === '42703') {
      return res.status(500).json({ message: DEPARTMENTS_SETUP_MESSAGE });
    }
    return res.status(500).json({ message: 'Could not add course.' });
  }
};

// PUT /courses/:courseCode  { course_name, department_id }
// The course code is not editable: schedules and students refer to it.
const updateCourse = async (req, res) => {
  const courseCode = String(req.params.courseCode ?? '').trim().toUpperCase();
  const courseName = String(req.body.course_name ?? '').trim();
  const departmentId = String(req.body.department_id ?? '').trim() || null;
  if (!courseName) {
    return res.status(400).json({ message: 'Course name is required.' });
  }
  if (courseName.length > 120) {
    return res.status(400).json({
      message: 'Course name must be at most 120 characters.'
    });
  }

  try {
    const result = await pool.query(
      `
      UPDATE courses
      SET course_name = $2, department_id = $3::uuid
      WHERE UPPER(course_code) = $1
      RETURNING course_code, course_name, department_id
      `,
      [courseCode, courseName, departmentId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ message: `Course "${courseCode}" was not found.` });
    }
    return res.json({ message: 'Course updated.', course: result.rows[0] });
  } catch (error) {
    console.error('Update course error:', error);
    if (error.code === '22P02' || error.code === '23503') {
      return res.status(400).json({ message: 'Choose a valid department.' });
    }
    if (error.code === '42P01' || error.code === '42703') {
      return res.status(500).json({ message: DEPARTMENTS_SETUP_MESSAGE });
    }
    return res.status(500).json({ message: 'Could not update the course.' });
  }
};

// DELETE /courses/:courseCode
// Refused while students or active class schedules still use the course.
const deleteCourse = async (req, res) => {
  const courseCode = String(req.params.courseCode ?? '').trim().toUpperCase();
  try {
    const exists = await pool.query(
      'SELECT 1 FROM courses WHERE UPPER(course_code) = $1',
      [courseCode]
    );
    if (exists.rowCount === 0) {
      return res.status(404).json({ message: `Course "${courseCode}" was not found.` });
    }

    const usage = await pool.query(
      `
      SELECT
        (SELECT COUNT(*) FROM class_schedules
          WHERE UPPER(BTRIM(course)) = $1 AND NOT is_archived)::int AS schedules,
        (SELECT COUNT(*) FROM students
          WHERE UPPER(BTRIM(course)) = $1)::int AS students
      `,
      [courseCode]
    );
    const { schedules, students } = usage.rows[0];
    if (schedules > 0 || students > 0) {
      const used = [];
      if (schedules > 0) used.push(`${schedules} class schedule(s)`);
      if (students > 0) used.push(`${students} student(s)`);
      return res.status(409).json({
        message: `Cannot delete ${courseCode}: it is still used by ${used.join(' and ')}.`
      });
    }

    await pool.query('DELETE FROM courses WHERE UPPER(course_code) = $1', [courseCode]);
    return res.json({ message: 'Course deleted.' });
  } catch (error) {
    console.error('Delete course error:', error);
    if (error.code === '23503') {
      return res.status(409).json({
        message: 'This course is still referenced by other records and cannot be deleted.'
      });
    }
    return res.status(500).json({ message: 'Could not delete the course.' });
  }
};

// ---------------------------------------------------------------- departments

const DEPARTMENTS_SETUP_MESSAGE =
  'The database is missing the departments setup. Run the departments SQL in pgAdmin, then restart the API.';

const readDepartmentBody = (body) => {
  const code = String(body.department_code ?? '').trim().toUpperCase();
  const name = String(body.department_name ?? '').trim();
  if (!code || !name) {
    return { error: 'Department code and department name are required.' };
  }
  if (code.length > 20 || name.length > 120) {
    return {
      error: 'Department code must be at most 20 characters and department name at most 120 characters.'
    };
  }
  return { code, name };
};

const getDepartments = async (req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        d.id,
        d.department_code,
        d.department_name,
        COUNT(c.course_code)::int AS course_count
      FROM departments d
      LEFT JOIN courses c ON c.department_id = d.id
      GROUP BY d.id, d.department_code, d.department_name
      ORDER BY d.department_name
      `
    );
    return res.json({ departments: result.rows });
  } catch (error) {
    console.error('Get departments error:', error);
    if (error.code === '42P01' || error.code === '42703') {
      return res.status(500).json({ message: DEPARTMENTS_SETUP_MESSAGE });
    }
    return res.status(500).json({ message: 'Could not load departments.' });
  }
};

const addDepartment = async (req, res) => {
  const { code, name, error: invalid } = readDepartmentBody(req.body);
  if (invalid) return res.status(400).json({ message: invalid });

  try {
    const sameName = await pool.query(
      'SELECT 1 FROM departments WHERE LOWER(BTRIM(department_name)) = LOWER($1)',
      [name]
    );
    if (sameName.rowCount > 0) {
      return res.status(409).json({
        message: `A department named "${name}" already exists.`
      });
    }
    const result = await pool.query(
      `
      INSERT INTO departments (department_code, department_name)
      VALUES ($1, $2)
      ON CONFLICT (department_code) DO NOTHING
      RETURNING id, department_code, department_name
      `,
      [code, name]
    );
    if (result.rowCount === 0) {
      return res.status(409).json({
        message: `Department code "${code}" already exists.`
      });
    }
    return res.status(201).json({
      message: 'Department added.',
      department: result.rows[0]
    });
  } catch (error) {
    console.error('Add department error:', error);
    if (error.code === '42P01' || error.code === '42703') {
      return res.status(500).json({ message: DEPARTMENTS_SETUP_MESSAGE });
    }
    return res.status(500).json({ message: 'Could not add the department.' });
  }
};

const updateDepartment = async (req, res) => {
  const { code, name, error: invalid } = readDepartmentBody(req.body);
  if (invalid) return res.status(400).json({ message: invalid });

  try {
    const sameName = await pool.query(
      `
      SELECT 1 FROM departments
      WHERE LOWER(BTRIM(department_name)) = LOWER($1) AND id <> $2::uuid
      `,
      [name, req.params.departmentId]
    );
    if (sameName.rowCount > 0) {
      return res.status(409).json({
        message: `A department named "${name}" already exists.`
      });
    }
    const result = await pool.query(
      `
      UPDATE departments
      SET department_code = $1, department_name = $2
      WHERE id = $3::uuid
      RETURNING id, department_code, department_name
      `,
      [code, name, req.params.departmentId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Department not found.' });
    }
    return res.json({
      message: 'Department updated.',
      department: result.rows[0]
    });
  } catch (error) {
    console.error('Update department error:', error);
    if (error.code === '23505') {
      return res.status(409).json({
        message: `Department code "${code}" already exists.`
      });
    }
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The department ID is invalid.' });
    }
    return res.status(500).json({ message: 'Could not update the department.' });
  }
};

// Refused while the department still has courses.
const deleteDepartment = async (req, res) => {
  try {
    const courses = await pool.query(
      'SELECT COUNT(*)::int AS total FROM courses WHERE department_id = $1::uuid',
      [req.params.departmentId]
    );
    if (courses.rows[0].total > 0) {
      return res.status(409).json({
        message: `This department still has ${courses.rows[0].total} course(s). Move or delete them first.`
      });
    }
    const result = await pool.query(
      'DELETE FROM departments WHERE id = $1::uuid',
      [req.params.departmentId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Department not found.' });
    }
    return res.json({ message: 'Department deleted.' });
  } catch (error) {
    console.error('Delete department error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The department ID is invalid.' });
    }
    return res.status(500).json({ message: 'Could not delete the department.' });
  }
};

const updateClassSchedule = async (req, res) => {
  const { scheduleId } = req.params;
  const {
    course,
    year_level: yearLevel,
    section,
    subject,
    weekday,
    start_time: rawStartTime,
    late_after: rawLateAfter,
    end_time: rawEndTime,
    teacher_email: rawTeacherEmail = '',
    instructor_name: rawInstructorName = '',
    campus_code: rawCampusCode = ''
  } = req.body;

  const normalized = {
    course: String(course ?? '').trim().toUpperCase(),
    yearLevel: String(yearLevel ?? '').trim().toUpperCase(),
    section: String(section ?? '').trim().toUpperCase(),
    subject: String(subject ?? '').trim().toUpperCase(),
    weekday: parseWeekday(weekday),
    startTime: normalizeTime(rawStartTime),
    lateAfter: normalizeTime(rawLateAfter),
    endTime: normalizeTime(rawEndTime),
    teacherEmail: String(rawTeacherEmail ?? '').trim().toLowerCase(),
    instructorName: String(rawInstructorName ?? '').trim(),
    campusCode: String(rawCampusCode ?? '').trim().toUpperCase()
  };

  const missing = ['course', 'year_level', 'subject', 'campus_code']
    .filter((field) => !req.body[field]?.toString().trim());
  if (missing.length > 0) {
    return res.status(400).json({
      message: `Required schedule fields are missing: ${missing.join(', ')}.`
    });
  }
  if (
    normalized.weekday === undefined ||
    !normalized.startTime ||
    !normalized.lateAfter ||
    !normalized.endTime
  ) {
    return res.status(400).json({
      message: 'Choose a valid weekday and valid start, late cutoff, and end times.'
    });
  }
  if (
    normalized.startTime >= normalized.lateAfter ||
    normalized.lateAfter >= normalized.endTime
  ) {
    return res.status(400).json({
      message: 'Times must be ordered start_time < late_after < end_time.'
    });
  }

  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    await client.query('LOCK TABLE class_schedules IN SHARE ROW EXCLUSIVE MODE');
    const teacherUserId = await findActiveTeacher(
      client,
      normalized.teacherEmail,
      normalized.instructorName
    );
    if (normalized.teacherEmail && !teacherUserId) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        message: `Teacher email "${normalized.teacherEmail}" is not an active registered teacher.`
      });
    }

    const campusResult = await client.query(
      `
      SELECT id
      FROM campuses
      WHERE UPPER(BTRIM(campus_code)) = $1
        AND boundary_coordinates IS NOT NULL
      `,
      [normalized.campusCode]
    );
    if (campusResult.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        message: `Campus "${normalized.campusCode}" was not found or has no configured boundary.`
      });
    }
    const campusId = campusResult.rows[0].id;

    const current = await client.query(
      `
      SELECT id
      FROM class_schedules
      WHERE id = $1::uuid AND NOT is_archived
      `,
      [scheduleId]
    );
    if (current.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Class schedule not found.' });
    }

    const overlap = await client.query(
      `
      SELECT id
      FROM class_schedules
      WHERE weekday = $1
        AND id <> $2::uuid
        AND NOT is_archived
        AND academic_term_id = (
          SELECT academic_term_id FROM class_schedules WHERE id = $2::uuid
        )
        AND (
          (
            UPPER(course) = $3
            AND UPPER(year_level) = $4
            AND UPPER(section) = $5
          )
          OR ($6::uuid IS NOT NULL AND teacher_user_id = $6)
        )
        AND start_time < $8::time
        AND end_time > $7::time
      LIMIT 1
      `,
      [
        normalized.weekday,
        scheduleId,
        normalized.course,
        normalized.yearLevel,
        normalized.section,
        teacherUserId,
        normalized.startTime,
        normalized.endTime
      ]
    );
    if (overlap.rowCount > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        message: 'This time overlaps another schedule for the same course/year/section or teacher.'
      });
    }

    const updated = await client.query(
      `
      UPDATE class_schedules
      SET course = $2,
          year_level = $3,
          section = $4,
          subject = $5,
          weekday = $6,
          start_time = $7::time,
          late_after = $8::time,
          end_time = $9::time,
          teacher_user_id = $10,
          instructor_name = NULLIF($11, ''),
          campus_id = $12::uuid,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = $1::uuid
      RETURNING id
      `,
      [
        scheduleId,
        normalized.course,
        normalized.yearLevel,
        normalized.section,
        normalized.subject,
        normalized.weekday,
        normalized.startTime,
        normalized.lateAfter,
        normalized.endTime,
        teacherUserId,
        normalized.instructorName,
        campusId
      ]
    );
    await client.query('COMMIT');
    return res.json({
      message: 'Class schedule updated.',
      scheduleId: updated.rows[0].id
    });
  } catch (error) {
    if (client) await client.query('ROLLBACK').catch(() => {});
    console.error('Update class schedule error:', error);
    if (error.code === '23505') {
      return res.status(409).json({
        message: 'This change duplicates an existing class schedule.'
      });
    }
    return res.status(400).json({
      message: error.code === '22P02'
        ? 'The class schedule ID is invalid.'
        : error.message || 'Could not update the class schedule.'
    });
  } finally {
    client?.release();
  }
};

const deleteClassSchedule = async (req, res) => {
  const { scheduleId } = req.params;
  try {
    const archived = await pool.query(
      `
      UPDATE class_schedules
      SET is_archived = TRUE, updated_at = CURRENT_TIMESTAMP
      WHERE id = $1::uuid AND NOT is_archived
      RETURNING id
      `,
      [scheduleId]
    );
    if (archived.rowCount > 0) {
      return res.json({
        message: 'Schedule archived. Any attendance history remains available.'
      });
    }

    const existing = await pool.query(
      'SELECT is_archived FROM class_schedules WHERE id = $1::uuid',
      [scheduleId]
    );
    if (existing.rowCount === 0) {
      return res.status(404).json({ message: 'Class schedule not found.' });
    }
    return res.status(409).json({ message: 'This schedule is already archived.' });
  } catch (error) {
    console.error('Delete class schedule error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The class schedule ID is invalid.' });
    }
    if (error.code === '23503') {
      return res.status(409).json({
        message: 'This schedule has attendance records and cannot be deleted. Edit it instead to preserve attendance history.'
      });
    }
    return res.status(500).json({ message: 'Could not delete the class schedule.' });
  }
};

const archiveCourseTermSchedules = async (req, res) => {
  const courseCode = String(req.params.courseCode ?? '').trim().toUpperCase();
  const termId = String(req.body.term_id ?? '');
  if (!courseCode || !termId) {
    return res.status(400).json({
      message: 'Course and academic term are required.'
    });
  }
  try {
    const result = await pool.query(
      `
      UPDATE class_schedules
      SET is_archived = TRUE, updated_at = CURRENT_TIMESTAMP
      WHERE UPPER(course) = $1
        AND academic_term_id = $2::uuid
        AND NOT is_archived
      RETURNING id
      `,
      [courseCode, termId]
    );
    return res.json({
      message: `${result.rowCount} schedule(s) archived. Attendance history is preserved.`,
      archived: result.rowCount
    });
  } catch (error) {
    console.error('Archive course schedules error:', error);
    return res.status(error.code === '22P02' ? 400 : 500).json({
      message: error.code === '22P02'
        ? 'The academic term is invalid.'
        : 'Could not archive the course schedules.'
    });
  }
};

const importClassSchedules = async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ message: 'Select a CSV or Excel schedule file.' });
  }

  const lateAfterMinutes = Number(req.body?.late_after_minutes ?? 30);
  const defaultCampusCode = String(req.body?.campus_code ?? '')
    .trim()
    .toUpperCase();
  if (!Number.isInteger(lateAfterMinutes) || lateAfterMinutes < 1 || lateAfterMinutes > 240) {
    return res.status(400).json({
      message: 'Late cutoff minutes must be a whole number from 1 to 240.'
    });
  }

  let client;
  try {
    client = await pool.connect();
    const courseCode = String(
      req.params.courseCode ?? req.body.course_code ?? ''
    ).trim().toUpperCase();
    // With a course code this is a single-course upload. Without one it is a
    // whole-school upload: every row names its own course in the `course` column.
    const isWholeSchool = !courseCode;
    let academicTermId;
    if (isWholeSchool) {
      const currentTerm = await client.query(
        'SELECT id FROM academic_terms WHERE is_current = TRUE'
      );
      if (currentTerm.rowCount === 0) {
        return res.status(409).json({
          message: 'Set up the current school year and semester before uploading schedules.'
        });
      }
      academicTermId = currentTerm.rows[0].id;
    } else {
      const registeredCourse = await client.query(
        `
        SELECT c.course_code, at.id AS academic_term_id
        FROM courses c
        CROSS JOIN academic_terms at
        WHERE c.course_code = $1 AND at.is_current = TRUE
        `,
        [courseCode]
      );
      if (registeredCourse.rowCount === 0) {
        const courseExists = await client.query(
          'SELECT 1 FROM courses WHERE course_code = $1',
          [courseCode]
        );
        if (courseExists.rowCount === 0) {
          return res.status(404).json({ message: `Course "${courseCode}" was not found. Add it first.` });
        }
        return res.status(409).json({
          message: 'Set up the current school year and semester before uploading schedules.'
        });
      }
      academicTermId = registeredCourse.rows[0].academic_term_id;
    }

    const rows = await readScheduleRows(req.file, {
      lateAfterMinutes,
      courseCode,
      defaultCampusCode
    });
    const schedules = parseRows(rows, courseCode, defaultCampusCode);
    if (schedules.length === 0) {
      return res.status(400).json({ message: 'The file contains no schedule rows.' });
    }

    const errors = schedules
      .filter((schedule) => schedule.error)
      .map((schedule) => schedule.error);
    if (isWholeSchool) {
      const firstRowByCourse = new Map();
      for (const schedule of schedules) {
        if (schedule.course && !firstRowByCourse.has(schedule.course)) {
          firstRowByCourse.set(schedule.course, schedule.rowNumber);
        }
      }
      const knownCourses = await client.query(
        'SELECT course_code FROM courses WHERE course_code = ANY($1::text[])',
        [[...firstRowByCourse.keys()]]
      );
      const known = new Set(knownCourses.rows.map((row) => row.course_code));
      for (const [course, rowNumber] of firstRowByCourse) {
        if (!known.has(course)) {
          errors.push(
            `Row ${rowNumber}: course "${course}" is not registered. Add it first.`
          );
        }
      }
    }
    const campusResult = await client.query(
      `
      SELECT id, campus_code
      FROM campuses
      WHERE boundary_coordinates IS NOT NULL
      `
    );
    const campusesByCode = new Map(
      campusResult.rows.map((campus) => [
        String(campus.campus_code).trim().toUpperCase(),
        campus.id
      ])
    );
    for (const schedule of schedules) {
      schedule.campusId = campusesByCode.get(schedule.campusCode);
      if (!schedule.campusId) {
        errors.push(
          `Row ${schedule.rowNumber}: campus "${schedule.campusCode || '(blank)'}" does not exist or has no configured boundary.`
        );
      }
    }
    if (errors.length > 0) {
      return res.status(400).json({ message: errors.join('\n') });
    }

    await client.query('BEGIN');
    await client.query('LOCK TABLE class_schedules IN SHARE ROW EXCLUSIVE MODE');
    const uploadedKeys = new Set();
    const processedSchedules = [];
    for (const schedule of schedules) {
      schedule.teacherUserId = await findActiveTeacher(
        client,
        schedule.teacherEmail,
        schedule.instructorName || ''
      );
      if (schedule.teacherEmail && !schedule.teacherUserId) {
        errors.push(
          `Row ${schedule.rowNumber}: teacher email "${schedule.teacherEmail}" is not an active registered teacher.`
        );
        continue;
      }

      const key = [
        schedule.course, schedule.yearLevel, schedule.section,
        schedule.subject, schedule.weekday, schedule.startTime
      ].join('|');
      if (uploadedKeys.has(key)) {
        errors.push(`Row ${schedule.rowNumber}: duplicate schedule row in this file.`);
        continue;
      }
      uploadedKeys.add(key);

      const groupKey = [
        schedule.course, schedule.yearLevel, schedule.section
      ].join('|');
      const startsAt = schedule.startTime;
      const endsAt = schedule.endTime;
      const uploadedConflict = processedSchedules.find((previous) =>
        previous.weekday === schedule.weekday &&
        (previous.groupKey === groupKey ||
          (schedule.teacherUserId != null &&
            previous.teacherUserId === schedule.teacherUserId)) &&
        previous.startTime < endsAt &&
        previous.endTime > startsAt
      );
      if (uploadedConflict) {
        const sameGroup = uploadedConflict.groupKey === groupKey;
        const sameTeacher = schedule.teacherUserId != null &&
          uploadedConflict.teacherUserId === schedule.teacherUserId;
        const weekdayNames = [
          'Sunday', 'Monday', 'Tuesday', 'Wednesday',
          'Thursday', 'Friday', 'Saturday'
        ];
        const conflictReason = sameGroup && sameTeacher
          ? 'the same class group and teacher'
          : sameGroup
            ? 'the same class group'
            : 'the same teacher';
        errors.push(
          `Row ${schedule.rowNumber} overlaps row ${uploadedConflict.rowNumber} on ${weekdayNames[schedule.weekday]} for ${conflictReason} (${uploadedConflict.startTime.slice(0, 5)}–${uploadedConflict.endTime.slice(0, 5)} and ${schedule.startTime.slice(0, 5)}–${schedule.endTime.slice(0, 5)}).`
        );
        continue;
      }
      processedSchedules.push({
        ...schedule,
        groupKey
      });
    }

    if (errors.length > 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: errors.join('\n') });
    }

    for (const schedule of schedules) {
      await client.query(
        `
        INSERT INTO class_schedules (
            academic_term_id, course, year_level, section, subject, weekday,
          start_time, late_after, end_time, teacher_user_id, instructor_name,
          campus_id
        )
          VALUES ($1::uuid, $2, $3, $4, $5, $6, $7::time, $8::time, $9::time, $10, $11, $12::uuid)
          ON CONFLICT ON CONSTRAINT class_schedules_term_course_year_subject_time_key
        DO UPDATE SET
          late_after = EXCLUDED.late_after,
          end_time = EXCLUDED.end_time,
          teacher_user_id = EXCLUDED.teacher_user_id,
          instructor_name = EXCLUDED.instructor_name,
          campus_id = EXCLUDED.campus_id,
            is_archived = FALSE,
            updated_at = CURRENT_TIMESTAMP
          `,
          [
            academicTermId,
            schedule.course, schedule.yearLevel, schedule.section,
            schedule.subject, schedule.weekday, schedule.startTime,
            schedule.lateAfter, schedule.endTime, schedule.teacherUserId,
          schedule.instructorName || null, schedule.campusId
        ]
      );
    }

    for (const schedule of schedules) {
      const overlap = await client.query(
        `
        SELECT id
        FROM class_schedules
        WHERE weekday = $1
          AND academic_term_id = $10::uuid
          AND NOT is_archived
          AND (
            (
              UPPER(course) = $2
              AND UPPER(year_level) = $3
              AND UPPER(section) = $4
            )
            OR ($5::uuid IS NOT NULL AND teacher_user_id = $5)
          )
          AND NOT (
            UPPER(course) = $2
            AND UPPER(year_level) = $3
            AND UPPER(section) = $4
            AND UPPER(subject) = $6
            AND start_time = $7::time
          )
          AND start_time < $9::time
          AND end_time > $8::time
        LIMIT 1
        `,
        [
          schedule.weekday, schedule.course, schedule.yearLevel,
          schedule.section, schedule.teacherUserId, schedule.subject,
          schedule.startTime, schedule.startTime, schedule.endTime,
          academicTermId
        ]
      );
      if (overlap.rows.length > 0) {
        errors.push(`Row ${schedule.rowNumber}: this class overlaps another schedule for the same section or teacher.`);
      }
    }
    if (errors.length > 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: errors.join('\n') });
    }

    await client.query('COMMIT');

    const unassignedInstructors = schedules.filter(
      (schedule) => schedule.teacherUserId == null && schedule.instructorName
    ).length;
    const courseCount = new Set(schedules.map((schedule) => schedule.course)).size;
    return res.json({
      message: `${schedules.length} class schedule row(s) imported or updated` +
        (isWholeSchool ? ` across ${courseCount} course(s).` : '.') +
        (unassignedInstructors > 0
          ? ` ${unassignedInstructors} instructor assignment(s) saved by name; teacher attendance is unavailable until accounts are linked.`
          : ''),
      imported: schedules.length
    });
  } catch (error) {
    if (client) await client.query('ROLLBACK').catch(() => {});
    console.error('Import class schedules error:', error);
    return res.status(400).json({
      message: error.message || 'Could not import the schedule file.'
    });
  } finally {
    client?.release();
  }
};

module.exports = {
  getCourses,
  addCourse,
  updateCourse,
  deleteCourse,
  getDepartments,
  addDepartment,
  updateDepartment,
  deleteDepartment,
  getClassSchedules,
  getAcademicTerms,
  createAcademicTerm,
  updateAcademicTerm,
  updateClassSchedule,
  deleteClassSchedule,
  archiveCourseTermSchedules,
  importClassSchedules,
  parseScheduleRows: parseRows,
  readScheduleRows
};