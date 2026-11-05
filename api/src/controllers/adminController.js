const crypto = require('crypto');
const { createCorrectionNotifications } = require('../services/notificationService');
const bcrypt = require('bcrypt');
const pool = require('../config/database');
const { sendAccountCredentials } = require('../services/emailService');

// A course belongs to a department, but a student record only carries the
// course code. This reads the one small table that links them, so the admin
// screens can offer a department filter above the course filter.
//
// The departments and courses tables are a later addition to the database. If
// an installation does not have them yet, this answers with an empty map and
// every list still loads; the department filter simply does not appear.
const departmentByCourse = async () => {
  try {
    const result = await pool.query(
      `
      SELECT
        UPPER(BTRIM(c.course_code)) AS course_code,
        d.department_name
      FROM courses c
      JOIN departments d ON d.id = c.department_id
      WHERE BTRIM(COALESCE(d.department_name, '')) <> ''
      `
    );
    const byCourse = new Map();
    for (const row of result.rows) {
      byCourse.set(row.course_code, row.department_name);
    }
    return byCourse;
  } catch (error) {
    // 42P01 = no such table, 42703 = no such column.
    if (error.code === '42P01' || error.code === '42703') return new Map();
    throw error;
  }
};

// Adds `department` to each row, read from its course.
const withDepartments = (rows, byCourse) =>
  rows.map((row) => ({
    ...row,
    department:
      byCourse.get(String(row.course ?? '').trim().toUpperCase()) ?? null
  }));

// GET /api/admin/summary
const getSummary = async (req, res) => {
  try {
    const studentsResult = await pool.query(
      `SELECT COUNT(*) FROM students`
    );
    const teachersResult = await pool.query(
      `SELECT COUNT(*) FROM teachers`
    );
    const parentsResult = await pool.query(
      `SELECT COUNT(*) FROM parents`
    );
    // CURRENT_DATE is the date of the server, which runs on UTC. Between
    // midnight and 8 AM in Manila that is still the previous day, so the count
    // has to be taken on the Manila date.
    const todayAttendanceResult = await pool.query(
      `
      SELECT COUNT(*) FROM attendance
      WHERE attendance_date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
      `
    );

    return res.json({
      totalStudents: parseInt(studentsResult.rows[0].count),
      totalTeachers: parseInt(teachersResult.rows[0].count),
      totalParents: parseInt(parentsResult.rows[0].count),
      totalAttendanceToday: parseInt(todayAttendanceResult.rows[0].count),
    });
  } catch (error) {
    console.error('Get summary error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// GET /api/admin/students
const getStudents = async (req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        s.id,
        s.user_id,
        s.parent_id,
        s.student_number,
        s.first_name,
        s.middle_name,
        s.last_name,
        s.course,
        s.year_level,
        s.section,
        u.email,
        u.status
      FROM students s
      JOIN users u ON u.id = s.user_id
      ORDER BY s.last_name, s.first_name
      `
    );

    const byCourse = await departmentByCourse();
    return res.json({ students: withDepartments(result.rows, byCourse) });
  } catch (error) {
    console.error('Get students error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// GET /api/admin/teachers
const getTeachers = async (req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        t.id,
        t.user_id,
        t.employee_number,
        t.first_name,
        t.middle_name,
        t.last_name,
        u.email,
        u.status
      FROM teachers t
      JOIN users u ON u.id = t.user_id
      ORDER BY t.last_name, t.first_name
      `
    );

    return res.json({ teachers: result.rows });
  } catch (error) {
    console.error('Get teachers error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// GET /api/admin/parents
const getParents = async (req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        p.id,
        p.user_id,
        p.first_name,
        p.middle_name,
        p.last_name,
        p.contact_number,
        u.email,
        u.status,
        COUNT(s.id) AS children_count
      FROM parents p
      JOIN users u ON u.id = p.user_id
      LEFT JOIN students s ON s.parent_id = p.id
      GROUP BY p.id, p.first_name, p.middle_name,
               p.last_name, p.contact_number,
               u.email, u.status
      ORDER BY p.last_name, p.first_name
      `
    );

    return res.json({ parents: result.rows });
  } catch (error) {
    console.error('Get parents error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

const linkParentChild = async (req, res) => {
  const parentId = String(req.params.parentId ?? '');
  const studentNumber = String(req.body.student_number ?? '').trim();
  if (!studentNumber) {
    return res.status(400).json({ message: 'Student ID is required.' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const parent = await client.query(
      'SELECT id FROM parents WHERE id = $1::uuid FOR UPDATE',
      [parentId]
    );
    if (parent.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Parent account was not found.' });
    }

    const student = await client.query(
      `
      SELECT id, parent_id
      FROM students
      WHERE UPPER(BTRIM(student_number)) = UPPER(BTRIM($1))
      FOR UPDATE
      `,
      [studentNumber]
    );
    if (student.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        message: 'No student was found with that ID. Check the ID and try again.'
      });
    }
    if (student.rows[0].parent_id && student.rows[0].parent_id !== parentId) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        message: 'This student is already linked to another parent.'
      });
    }

    await client.query(
      'UPDATE students SET parent_id = $1::uuid WHERE id = $2::uuid',
      [parentId, student.rows[0].id]
    );
    await client.query('COMMIT');
    return res.json({ message: 'Student linked to parent successfully.' });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Link parent child error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The parent ID is invalid.' });
    }
    return res.status(500).json({ message: 'Could not link student to parent.' });
  } finally {
    client.release();
  }
};

const unlinkParentChild = async (req, res) => {
  const { parentId, studentId } = req.params;
  try {
    const result = await pool.query(
      `
      UPDATE students
      SET parent_id = NULL
      WHERE id = $1::uuid AND parent_id = $2::uuid
      `,
      [studentId, parentId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({
        message: 'The student is not linked to this parent.'
      });
    }
    return res.json({ message: 'Student unlinked from parent.' });
  } catch (error) {
    console.error('Unlink parent child error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The parent or student ID is invalid.' });
    }
    return res.status(500).json({ message: 'Could not unlink student from parent.' });
  }
};

const updateManagedUser = async (req, res) => {
  const userId = String(req.params.userId ?? '');
  const {
    email,
    first_name: firstName,
    middle_name: middleName,
    last_name: lastName
  } = req.body;
  const normalizedEmail = String(email ?? '').trim().toLowerCase();
  const normalizedFirstName = String(firstName ?? '').trim();
  const normalizedMiddleName = String(middleName ?? '').trim();
  const normalizedLastName = String(lastName ?? '').trim();

  if (!normalizedEmail || !normalizedFirstName || !normalizedLastName) {
    return res.status(400).json({
      message: 'Email, first name, and last name are required.'
    });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
    return res.status(400).json({ message: 'Enter a valid email address.' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const account = await client.query(
      `
      SELECT u.id, LOWER(r.name) AS role
      FROM users u
      JOIN user_roles ur ON ur.user_id = u.id
      JOIN roles r ON r.id = ur.role_id
      WHERE u.id = $1::uuid
        AND LOWER(r.name) IN ('student', 'teacher', 'parent')
      FOR UPDATE OF u
      `,
      [userId]
    );
    if (account.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        message: 'Managed user not found.'
      });
    }

    await client.query(
      `
      UPDATE users
      SET email = $2, updated_at = CURRENT_TIMESTAMP
      WHERE id = $1::uuid
      `,
      [userId, normalizedEmail]
    );

    const role = account.rows[0].role;
    let profileUpdate;
    if (role === 'student') {
      const studentNumber = String(req.body.student_number ?? '').trim();
      const course = String(req.body.course ?? '').trim();
      const yearLevel = String(req.body.year_level ?? '').trim();
      const section = String(req.body.section ?? '').trim();
      if (!studentNumber || !course || !yearLevel) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          message: 'Student number, course, and year level are required.'
        });
      }
      profileUpdate = await client.query(
        `
        UPDATE students
        SET student_number = $2, first_name = $3, middle_name = NULLIF($4, ''),
            last_name = $5, course = $6, year_level = $7, section = NULLIF($8, '')
        WHERE user_id = $1::uuid
        `,
        [
          userId, studentNumber, normalizedFirstName, normalizedMiddleName,
          normalizedLastName, course, yearLevel, section
        ]
      );
    } else if (role === 'teacher') {
      const employeeNumber = String(req.body.employee_number ?? '').trim();
      if (!employeeNumber) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          message: 'Employee number is required.'
        });
      }
      profileUpdate = await client.query(
        `
        UPDATE teachers
        SET employee_number = $2, first_name = $3, middle_name = NULLIF($4, ''),
            last_name = $5
        WHERE user_id = $1::uuid
        `,
        [
          userId, employeeNumber, normalizedFirstName, normalizedMiddleName,
          normalizedLastName
        ]
      );
    } else {
      const contactNumber = String(req.body.contact_number ?? '').trim();
      profileUpdate = await client.query(
        `
        UPDATE parents
        SET first_name = $2, middle_name = NULLIF($3, ''),
            last_name = $4, contact_number = NULLIF($5, '')
        WHERE user_id = $1::uuid
        `,
        [
          userId, normalizedFirstName, normalizedMiddleName,
          normalizedLastName, contactNumber
        ]
      );
    }

    if (profileUpdate.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        message: 'User profile was not found; no changes were saved.'
      });
    }
    await client.query('COMMIT');
    return res.json({ message: 'User profile updated.' });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Update managed user error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The user ID is invalid.' });
    }
    if (error.code === '23505') {
      return res.status(409).json({
        message: 'That email or ID number is already assigned to another account.'
      });
    }
    return res.status(500).json({ message: 'Could not update the user profile.' });
  } finally {
    client.release();
  }
};

const setManagedUserStatus = async (req, res) => {
  const userId = String(req.params.userId ?? '');
  const status = String(req.body.status ?? '').trim().toLowerCase();
  if (status !== 'active' && status !== 'inactive') {
    return res.status(400).json({
      message: 'Account status must be active or inactive.'
    });
  }
  if (status === 'inactive' && userId === req.user.userId) {
    return res.status(409).json({
      message: 'You cannot deactivate your own administrator account.'
    });
  }

  try {
    const result = await pool.query(
      `
      UPDATE users u
      SET status = $2, updated_at = CURRENT_TIMESTAMP
      WHERE u.id = $1::uuid
        AND EXISTS (
          SELECT 1
          FROM user_roles ur
          JOIN roles r ON r.id = ur.role_id
          WHERE ur.user_id = u.id
            AND LOWER(r.name) IN ('student', 'teacher', 'parent')
        )
      RETURNING u.status
      `,
      [userId, status]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Managed user not found.' });
    }
    return res.json({
      message: status === 'inactive'
        ? 'Account deactivated. Attendance and profile history were preserved.'
        : 'Account reactivated.',
      status: result.rows[0].status
    });
  } catch (error) {
    console.error('Set managed user status error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The user ID is invalid.' });
    }
    return res.status(500).json({ message: 'Could not update account status.' });
  }
};


// ---------------------------------------------------------------------------
// Adding one teacher account.
//
// Students and parents arrive in bulk from the registrar's master list.
// Teachers are few and are added one at a time here, which is what replaced
// self-registration. The account is made the same way as in the bulk import:
// a random temporary password, emailed to the teacher, which the system then
// forces them to change at the first sign-in.
// ---------------------------------------------------------------------------

// Letters and digits that cannot be mistaken for one another when typed from
// an email: no O/0, no l/I/1.
const UPPER = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const LOWER = 'abcdefghijkmnopqrstuvwxyz';
const DIGITS = '23456789';

const generateTempPassword = () => {
  const pick = (set) => set[crypto.randomInt(set.length)];
  const all = UPPER + LOWER + DIGITS;
  const chars = [pick(UPPER), pick(LOWER), pick(DIGITS)];
  while (chars.length < 10) chars.push(pick(all));
  for (let i = chars.length - 1; i > 0; i -= 1) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
};

const describeEmailError = (error) => {
  const text = String(error?.response ?? error?.message ?? '');
  if (text.startsWith('Email delivery is not configured')) {
    return 'Email delivery is not configured.';
  }
  if (error?.code === 'EAUTH') {
    return 'The email server rejected the sign-in. Check the SMTP settings.';
  }
  if (/quota|limit exceeded|too many/i.test(text)) {
    return 'The daily email limit was reached. Try again later.';
  }
  if (error?.code === 'EENVELOPE' || /recipient|invalid.*address/i.test(text)) {
    return 'The email address was rejected.';
  }
  return 'The email could not be sent.';
};

const collapse = (value) => String(value ?? '').replace(/\s+/g, ' ').trim();

// POST /api/admin/teachers
const addTeacher = async (req, res) => {
  const email = collapse(req.body.email).toLowerCase();
  const firstName = collapse(req.body.first_name);
  const middleName = collapse(req.body.middle_name);
  const lastName = collapse(req.body.last_name);
  const employeeNumber = collapse(req.body.employee_number);

  if (!firstName || !lastName || !email || !employeeNumber) {
    return res.status(400).json({
      message: 'First name, last name, email and employee number are required.'
    });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ message: 'Enter a valid email address.' });
  }

  const client = await pool.connect();
  let created = null;
  try {
    await client.query('BEGIN');

    const role = await client.query(
      `SELECT id FROM roles WHERE LOWER(name) = 'teacher'`
    );
    if (role.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(500).json({
        message: 'The teacher role was not found in the roles table.'
      });
    }

    const takenEmail = await client.query(
      `SELECT 1 FROM users WHERE LOWER(BTRIM(email)) = $1`,
      [email]
    );
    if (takenEmail.rowCount > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        message: 'That email address already has an account.'
      });
    }

    const takenNumber = await client.query(
      `SELECT 1 FROM teachers WHERE UPPER(BTRIM(employee_number)) = UPPER($1)`,
      [employeeNumber]
    );
    if (takenNumber.rowCount > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        message: 'That employee number is already used by another teacher.'
      });
    }

    const tempPassword = generateTempPassword();
    const account = await client.query(
      `
      INSERT INTO users (id, email, password_hash, status, email_verified, must_change_password)
      VALUES (gen_random_uuid(), $1, $2, 'active', TRUE, TRUE)
      RETURNING id
      `,
      [email, await bcrypt.hash(tempPassword, 10)]
    );
    const userId = account.rows[0].id;

    await client.query(
      `INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2)`,
      [userId, role.rows[0].id]
    );
    await client.query(
      `
      INSERT INTO teachers (id, user_id, employee_number, first_name, middle_name, last_name)
      VALUES (gen_random_uuid(), $1, $2, $3, NULLIF($4, ''), $5)
      `,
      [userId, employeeNumber, firstName, middleName, lastName]
    );

    await client.query('COMMIT');
    created = { userId, tempPassword };
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Add teacher error:', error);
    if (error.code === '23505') {
      return res.status(409).json({
        message: 'That email or employee number is already used by another account.'
      });
    }
    return res.status(500).json({ message: 'Could not add the teacher.' });
  } finally {
    client.release();
  }

  // The account exists from here on. A failed email must not undo it: the
  // administrator is told instead, and can send the password again.
  const fullName = [firstName, middleName, lastName].filter(Boolean).join(' ');
  try {
    await sendAccountCredentials({
      email,
      fullName,
      role: 'teacher',
      tempPassword: created.tempPassword
    });
  } catch (error) {
    console.error('Add teacher email error:', error);
    return res.status(201).json({
      message: `${fullName} was added, but the email could not be sent.`,
      user_id: created.userId,
      email_sent: false,
      email_error: describeEmailError(error)
    });
  }

  return res.status(201).json({
    message: `${fullName} was added. The temporary password was emailed to ${email}.`,
    user_id: created.userId,
    email_sent: true
  });
};

// GET /api/admin/campuses
const resetStudentDevice = async (req, res) => {
  const userId = String(req.params.userId ?? '');
  try {
    const student = await pool.query(
      'SELECT user_id FROM students WHERE user_id = $1::uuid',
      [userId]
    );
    if (student.rowCount === 0) {
      return res.status(404).json({ message: 'Student not found.' });
    }
    const removed = await pool.query(
      'DELETE FROM student_devices WHERE user_id = $1::uuid RETURNING user_id',
      [userId]
    );
    return res.json({
      message: removed.rowCount > 0
        ? 'The linked phone was reset. The student can sign in on a new phone, and any open login was ended.'
        : 'This student has no linked phone yet.'
    });
  } catch (error) {
    console.error('Reset student device error:', error);
    return res.status(500).json({ message: 'Could not reset the linked phone.' });
  }
};

const getCampuses = async (req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        id,
        campus_code,
        campus_name,
        latitude,
        longitude,
        boundary_coordinates::json AS boundary_coordinates
      FROM campuses
      ORDER BY campus_name
      `
    );

    return res.json({ campuses: result.rows });
  } catch (error) {
    console.error('Get campuses error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// PUT /api/admin/campuses/:id/boundary
const updateCampusBoundary = async (req, res) => {
  try {
    const { id } = req.params;
    const { coordinates } = req.body;

    if (!coordinates || coordinates.length < 3) {
      return res.status(400).json({
        message: 'At least 3 boundary points are required.'
      });
    }

    // Close the polygon by repeating the first point at the end
    const closedCoordinates = [...coordinates];
    const first = coordinates[0];
    const last = coordinates[coordinates.length - 1];
    if (first[0] !== last[0] || first[1] !== last[1]) {
      closedCoordinates.push(first);
    }

    const boundaryGeoJSON = {
      type: 'Polygon',
      coordinates: [closedCoordinates]
    };

    await pool.query(
      `
      UPDATE campuses
      SET boundary_coordinates = $1::jsonb
      WHERE id = $2
      `,
      [JSON.stringify(boundaryGeoJSON), id]
    );

    return res.json({
      message: 'Campus boundary updated successfully.'
    });
  } catch (error) {
    console.error('Update boundary error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// POST /api/admin/campuses
const addCampus = async (req, res) => {
  console.log('addCampus hit', req.body);
  try {
    const { campus_name, campus_code, latitude, longitude } = req.body;

    if (!campus_name || !campus_code || !latitude || !longitude) {
      return res.status(400).json({
        message: 'Campus name, code, latitude, and longitude are required.'
      });
    }

    // Check if campus code already exists
    const existing = await pool.query(
      `SELECT id FROM campuses WHERE campus_code = $1`,
      [campus_code.toUpperCase()]
    );

    if (existing.rows.length > 0) {
      return res.status(400).json({
        message: 'Campus code already exists.'
      });
    }

    const result = await pool.query(
      `
      INSERT INTO campuses (id, campus_code, campus_name, latitude, longitude)
      VALUES (gen_random_uuid(), $1, $2, $3, $4)
      RETURNING id, campus_code, campus_name, latitude, longitude
      `,
      [campus_code.toUpperCase(), campus_name, parseFloat(latitude), parseFloat(longitude)]
    );

    return res.status(201).json({
      message: 'Campus added successfully.',
      campus: result.rows[0]
    });
  } catch (error) {
    console.error('Add campus error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// DELETE /api/admin/campuses/:id
const deleteCampus = async (req, res) => {
  try {
    const { id } = req.params;

    // Check if campus exists
    const campusResult = await pool.query(
      `SELECT id, campus_name FROM campuses WHERE id = $1`,
      [id]
    );

    if (campusResult.rows.length === 0) {
      return res.status(404).json({
        message: 'Campus not found.'
      });
    }

    // Check if campus has attendance records
    const attendanceResult = await pool.query(
      `SELECT COUNT(*) FROM attendance WHERE campus_id = $1`,
      [id]
    );

    const count = parseInt(attendanceResult.rows[0].count);

    if (count > 0) {
      return res.status(400).json({
        message: `Cannot delete campus. It has ${count} existing attendance record(s).`
      });
    }

    // Safe to delete
    await pool.query(
      `DELETE FROM campuses WHERE id = $1`,
      [id]
    );

    return res.json({
      message: 'Campus deleted successfully.'
    });
  } catch (error) {
    console.error('Delete campus error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// GET /api/admin/attendance
// GET /api/admin/attendance
//
// Students only. Teachers stopped recording attendance when they became
// viewers, so a role filter has nothing left to choose between. Their old
// records are still in the database, they are simply not listed here.
// Each row carries the student's course and year level so the app can filter
// by them.
// GET /api/admin/attendance/trend?days=7
//
// How many students came to campus on each of the last few days, and how many
// of them were late, for the chart on the admin dashboard. Days are Manila
// days, counted back from today in Manila, whatever time zone the server runs
// in. A day with nobody is still listed, with zeros, so the chart has no gaps.
// A student who timed in twice in a day is one student that day; a student
// late on any of those visits counts as late. Only reads; nothing is stored.
const getAttendanceTrend = async (req, res) => {
  try {
    const requested = Number.parseInt(req.query.days, 10);
    const days = Number.isInteger(requested)
      ? Math.min(Math.max(requested, 1), 31)
      : 7;

    const result = await pool.query(
      `
      WITH days AS (
        SELECT generate_series(
          (NOW() AT TIME ZONE 'Asia/Manila')::date - ($1::int - 1),
          (NOW() AT TIME ZONE 'Asia/Manila')::date,
          INTERVAL '1 day'
        )::date AS day
      )
      SELECT
        d.day::text AS date,
        COUNT(DISTINCT s.user_id) AS students,
        COUNT(DISTINCT s.user_id) FILTER (
          WHERE LOWER(a.status) = 'late'
        ) AS late
      FROM days d
      LEFT JOIN attendance a ON a.attendance_date = d.day
      LEFT JOIN students s ON s.user_id = a.user_id
      GROUP BY d.day
      ORDER BY d.day
      `,
      [days]
    );

    return res.json({
      days,
      trend: result.rows.map((row) => ({
        date: row.date,
        students: Number(row.students) || 0,
        late: Number(row.late) || 0
      }))
    });
  } catch (error) {
    console.error('Get attendance trend error:', error);
    return res.status(500).json({ message: 'Could not load the attendance trend.' });
  }
};

const getAttendance = async (req, res) => {
  try {
    const { date } = req.query;

    if (date) {
      const datePattern = /^\d{4}-\d{2}-\d{2}$/;
      const parsedDate = new Date(`${date}T00:00:00.000Z`);
      if (
        typeof date !== 'string' ||
        !datePattern.test(date) ||
        Number.isNaN(parsedDate.getTime()) ||
        parsedDate.toISOString().slice(0, 10) !== date
      ) {
        return res.status(400).json({
          message: 'Date must be a valid date in YYYY-MM-DD format.'
        });
      }
    }

    // The join to students is what keeps this to students only.
    let query = `
      SELECT
        a.id,
        TO_CHAR(
          COALESCE(a.time_in::date, a.attendance_date),
          'YYYY-MM-DD'
        ) AS attendance_date,
        TO_CHAR(a.time_in, 'YYYY-MM-DD"T"HH24:MI:SS') AS time_in,
        TO_CHAR(a.time_out, 'YYYY-MM-DD"T"HH24:MI:SS') AS time_out,
        a.status,
        a.latitude_in,
        a.longitude_in,
        c.campus_name,
        u.email,
        s.first_name || ' ' || s.last_name AS full_name,
        s.student_number AS id_number,
        s.course,
        s.year_level,
        corr.remarks AS correction_remarks,
        a.user_id
      FROM attendance a
      JOIN students s ON s.user_id = a.user_id
      JOIN users u ON u.id = a.user_id
      LEFT JOIN campuses c ON c.id = a.campus_id
      -- The latest correction of this record, if any, with its reason. It is
      -- kept in the notifications sent about it (see notificationService).
      LEFT JOIN LATERAL (
        SELECT n.metadata->>'remarks' AS remarks, n.created_at
        FROM notifications n
        WHERE n.metadata->>'event' = 'attendance_corrected'
          AND n.metadata->>'attendance_id' = a.id::text
        ORDER BY n.created_at DESC
        LIMIT 1
      ) corr ON TRUE
    `;

    const params = [];

    const filters = [];
    if (date) {
      params.push(date);
      filters.push(
        `COALESCE(a.time_in::date, a.attendance_date) = $${params.length}::date`
      );
    }

    if (filters.length > 0) {
      query += ` WHERE ${filters.join(' AND ')}`;
    }

    query += ` ORDER BY a.attendance_date DESC, a.time_in DESC`;

    const result = await pool.query(query, params);

    const byCourse = await departmentByCourse();
    return res.json({ attendance: withDepartments(result.rows, byCourse) });
  } catch (error) {
    console.error('Get attendance error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// PUT /api/admin/attendance/:id
const correctAttendance = async (req, res) => {
  try {
    const { id } = req.params;
    const { time_in, time_out, status } = req.body;
    const remarks = String(req.body?.remarks ?? '').replace(/\s+/g, ' ').trim();

    if (!time_in && !time_out && !status) {
      return res.status(400).json({
        message: 'At least one field (time_in, time_out, status) is required.'
      });
    }
    // Every correction says why. The reason is what the student, the parent
    // and a later reader of the record are told.
    if (remarks.length < 3) {
      return res.status(400).json({
        message: 'Write a short reason for the correction (remarks).'
      });
    }
    if (remarks.length > 300) {
      return res.status(400).json({
        message: 'Keep the remarks to 300 characters or fewer.'
      });
    }

    const allowedStatuses = ['present', 'late', 'absent', 'timeout'];
    if (status && !allowedStatuses.includes(String(status).toLowerCase())) {
      return res.status(400).json({
        message: 'Status must be present, late, absent or timeout.'
      });
    }
    // Manila wall-clock text, as the app sends it: 2026-11-02T07:30:00.
    const timePattern = /^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/;
    for (const [label, value] of [['Time in', time_in], ['Time out', time_out]]) {
      if (value && !timePattern.test(String(value))) {
        return res.status(400).json({
          message: `${label} must look like 2026-11-02T07:30:00.`
        });
      }
    }

    // Check if record exists, and read its times so a change to one of them
    // can be checked against the other.
    const existing = await pool.query(
      `
      SELECT
        id,
        status,
        TO_CHAR(time_in, 'YYYY-MM-DD"T"HH24:MI:SS') AS time_in,
        TO_CHAR(time_out, 'YYYY-MM-DD"T"HH24:MI:SS') AS time_out
      FROM attendance
      WHERE id = $1
      `,
      [id]
    );

    if (existing.rows.length === 0) {
      return res.status(404).json({
        message: 'Attendance record not found.'
      });
    }

    // A time out must come after the time in, whichever of the two changes.
    const pad = (value) => (value && value.length === 16 ? `${value}:00` : value);
    const newIn = pad(time_in) || existing.rows[0].time_in;
    const newOut = pad(time_out) || existing.rows[0].time_out;
    if (newIn && newOut && newOut <= newIn) {
      return res.status(400).json({
        message: 'Time out must be later than time in.'
      });
    }

    // Build dynamic update query
    const fields = [];
    const values = [];
    let counter = 1;

    if (time_in) {
      fields.push(`time_in = $${counter}`);
      values.push(time_in);
      counter++;
    }
    if (time_out) {
      fields.push(`time_out = $${counter}`);
      values.push(time_out);
      counter++;
    }
    if (status) {
      fields.push(`status = $${counter}`);
      values.push(String(status).toLowerCase());
      counter++;
    }

    fields.push(`updated_at = NOW()`);
    values.push(id);

    await pool.query(
      `UPDATE attendance SET ${fields.join(', ')} WHERE id = $${counter}`,
      values
    );

    // What changed, in words: "Time in 7:30 AM -> 8:00 AM".
    const before = existing.rows[0];
    const clock = (text) => {
      const match = /T(\d{2}):(\d{2})/.exec(String(text ?? ''));
      if (!match) return 'none';
      const hour = Number(match[1]);
      return `${hour % 12 === 0 ? 12 : hour % 12}:${match[2]} ${hour >= 12 ? 'PM' : 'AM'}`;
    };
    const statusName = (value) => {
      const text = String(value ?? '').toLowerCase();
      if (text === 'timeout') return 'Auto timed out';
      return text ? text[0].toUpperCase() + text.slice(1) : 'none';
    };
    const changes = [];
    if (time_in && clock(pad(time_in)) !== clock(before.time_in)) {
      changes.push(`Time in ${clock(before.time_in)} -> ${clock(pad(time_in))}`);
    }
    if (time_out && clock(pad(time_out)) !== clock(before.time_out)) {
      changes.push(`Time out ${clock(before.time_out)} -> ${clock(pad(time_out))}`);
    }
    if (status && String(status).toLowerCase() !== String(before.status ?? '').toLowerCase()) {
      changes.push(`Status ${statusName(before.status)} -> ${statusName(status)}`);
    }

    // The record is already corrected; a failure to write the note is
    // reported, not allowed to undo it.
    let notificationWarning;
    try {
      await createCorrectionNotifications({
        attendanceId: id,
        remarks,
        changes,
        adminUserId: req.user?.userId
      });
    } catch (error) {
      console.error('Correction notification error:', error);
      notificationWarning =
        'The record was corrected, but the student and parent could not be notified.';
    }

    return res.json({
      message: 'Attendance record updated successfully.',
      changes,
      ...(notificationWarning ? { notificationWarning } : {})
    });
  } catch (error) {
    console.error('Correct attendance error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// GET /api/admin/report/users
// GET /api/admin/report/users
//
// Students only, for the same reason as the attendance list above. Course and
// year level go out with each row so the app can filter by them instead of by
// role.
const getReportUsers = async (req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        u.id AS user_id,
        s.first_name || ' ' || s.last_name AS full_name,
        s.student_number AS id_number,
        s.course,
        s.year_level,
        u.email
      FROM users u
      JOIN students s ON s.user_id = u.id
      ORDER BY full_name
      `
    );
    const byCourse = await departmentByCourse();
    return res.json({ users: withDepartments(result.rows, byCourse) });
  } catch (error) {
    console.error('Get report users error:', error);
    return res.status(500).json({ message: 'Internal server error.' });
  }
};

// GET /api/admin/report/users/:userId
const getUserAttendanceReport = async (req, res) => {
  try {
    const { userId } = req.params;
    const result = await pool.query(
      `
      SELECT
        a.id,
        -- Dates and times go out as plain text, never as JSON dates. time_in
        -- and time_out hold Manila wall clock, and a JSON date would be moved
        -- by the time zone of the server (UTC on Vercel).
        a.attendance_date::text AS attendance_date,
        TO_CHAR(a.time_in, 'YYYY-MM-DD"T"HH24:MI:SS') AS time_in,
        TO_CHAR(a.time_out, 'YYYY-MM-DD"T"HH24:MI:SS') AS time_out,
        a.status,
        c.campus_name,
        corr.remarks AS correction_remarks
      FROM attendance a
      LEFT JOIN campuses c ON c.id = a.campus_id
      LEFT JOIN LATERAL (
        SELECT n.metadata->>'remarks' AS remarks
        FROM notifications n
        WHERE n.metadata->>'event'='attendance_corrected'
          AND n.metadata->>'attendance_id'=a.id::text
        ORDER BY n.created_at DESC LIMIT 1
      ) corr ON TRUE
      WHERE a.user_id = $1
      ORDER BY a.attendance_date DESC, a.time_in DESC
      `,
      [userId]
    );
    return res.json({ attendance: result.rows });
  } catch (error) {
    console.error('Get user attendance report error:', error);
    return res.status(500).json({ message: 'Internal server error.' });
  }
};

module.exports = {
  getSummary,
  getStudents,
  getTeachers,
  addTeacher,
  getParents,
  linkParentChild,
  unlinkParentChild,
  updateManagedUser,
  setManagedUserStatus,
  resetStudentDevice,
  getCampuses,
  updateCampusBoundary,
  addCampus,
  deleteCampus,
  getAttendance,
  getAttendanceTrend,
  correctAttendance,
  getReportUsers,
  getUserAttendanceReport,
};