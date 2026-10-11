const pool = require('../config/database');

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
    const todayAttendanceResult = await pool.query(
      `
      SELECT COUNT(*) FROM attendance
      WHERE attendance_date = CURRENT_DATE
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

    return res.json({ students: result.rows });
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

// GET /api/admin/campuses
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
const getAttendance = async (req, res) => {
  try {
    const { date, role } = req.query;

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

    const allowedRoles = ['Student', 'Teacher'];
    if (role && (typeof role !== 'string' || !allowedRoles.some(
      (allowedRole) => allowedRole.toLowerCase() === role.toLowerCase()
    ))) {
      return res.status(400).json({
        message: 'Invalid attendance role filter.'
      });
    }

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
        cs.subject AS class_subject,
        a.latitude_in,
        a.longitude_in,
        c.campus_name,
        u.email,
        COALESCE(
          s.first_name || ' ' || s.last_name,
          t.first_name || ' ' || t.last_name
        ) AS full_name,
        COALESCE(
          s.student_number,
          t.employee_number
        ) AS id_number,
        r.name AS role
      FROM attendance a
      JOIN users u ON u.id = a.user_id
      LEFT JOIN students s ON s.user_id = a.user_id
      LEFT JOIN teachers t ON t.user_id = a.user_id
      LEFT JOIN campuses c ON c.id = a.campus_id
      LEFT JOIN class_schedules cs ON cs.id = a.class_schedule_id
      LEFT JOIN user_roles ur ON ur.user_id = a.user_id
      LEFT JOIN roles r ON r.id = ur.role_id
    `;

    const params = [];

    const filters = [];
    if (date) {
      params.push(date);
      filters.push(
        `COALESCE(a.time_in::date, a.attendance_date) = $${params.length}::date`
      );
    }
    if (role) {
      params.push(role);
      filters.push(`LOWER(r.name) = LOWER($${params.length})`);
    }

    if (filters.length > 0) {
      query += ` WHERE ${filters.join(' AND ')}`;
    }

    query += ` ORDER BY a.attendance_date DESC, a.time_in DESC`;

    const result = await pool.query(query, params);

    return res.json({ attendance: result.rows });
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

    if (!time_in && !time_out && !status) {
      return res.status(400).json({
        message: 'At least one field (time_in, time_out, status) is required.'
      });
    }

    // Check if record exists
    const existing = await pool.query(
      `SELECT id FROM attendance WHERE id = $1`,
      [id]
    );

    if (existing.rows.length === 0) {
      return res.status(404).json({
        message: 'Attendance record not found.'
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
      values.push(status);
      counter++;
    }

    fields.push(`updated_at = NOW()`);
    values.push(id);

    await pool.query(
      `UPDATE attendance SET ${fields.join(', ')} WHERE id = $${counter}`,
      values
    );

    return res.json({
      message: 'Attendance record updated successfully.'
    });
  } catch (error) {
    console.error('Correct attendance error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// GET /api/admin/report/users
const getReportUsers = async (req, res) => {
  try {
    const { role } = req.query;
    const allowedRoles = ['Student', 'Teacher'];
    if (role && (typeof role !== 'string' || !allowedRoles.some(
      (allowedRole) => allowedRole.toLowerCase() === role.toLowerCase()
    ))) {
      return res.status(400).json({
        message: 'Invalid report role filter.'
      });
    }

    const params = [];
    let roleFilter = `r.name IN ('Student', 'Teacher')`;
    if (role) {
      params.push(role);
      roleFilter = `LOWER(r.name) = LOWER($${params.length})`;
    }

    const result = await pool.query(
      `
      SELECT
        u.id AS user_id,
        COALESCE(
          s.first_name || ' ' || s.last_name,
          t.first_name || ' ' || t.last_name
        ) AS full_name,
        COALESCE(s.student_number, t.employee_number) AS id_number,
        r.name AS role,
        u.email
      FROM users u
      LEFT JOIN students s ON s.user_id = u.id
      LEFT JOIN teachers t ON t.user_id = u.id
      LEFT JOIN user_roles ur ON ur.user_id = u.id
      LEFT JOIN roles r ON r.id = ur.role_id
      WHERE ${roleFilter}
      ORDER BY full_name
      `,
      params
    );
    return res.json({ users: result.rows });
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
        a.attendance_date,
        a.time_in,
        a.time_out,
        a.status,
        c.campus_name,
        cs.subject AS class_subject
      FROM attendance a
      LEFT JOIN campuses c ON c.id = a.campus_id
      LEFT JOIN class_schedules cs ON cs.id = a.class_schedule_id
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
  getParents,
  linkParentChild,
  unlinkParentChild,
  updateManagedUser,
  setManagedUserStatus,
  getCampuses,
  updateCampusBoundary,
  addCampus,
  deleteCampus,
  getAttendance,
  correctAttendance,
  getReportUsers,
  getUserAttendanceReport,
};