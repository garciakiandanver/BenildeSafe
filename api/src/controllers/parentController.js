const pool = require('../config/database');

// GET /api/parent/children
// Returns all children linked to the logged-in parent
const getChildren = async (req, res) => {
  try {
    const userId = req.user.userId;

    // Get the parent record for this user
    const parentResult = await pool.query(
      `SELECT id FROM parents WHERE user_id = $1`,
      [userId]
    );

    if (parentResult.rows.length === 0) {
      return res.status(404).json({
        message: 'Parent profile not found.'
      });
    }

    const parentId = parentResult.rows[0].id;

    // Get all children linked to this parent
    const childrenResult = await pool.query(
      `
      SELECT
        s.id,
        s.student_number,
        s.first_name,
        s.middle_name,
        s.last_name,
        s.course,
        s.year_level,
        s.section
      FROM students s
      WHERE s.parent_id = $1
      ORDER BY s.first_name
      `,
      [parentId]
    );

    return res.json({
      children: childrenResult.rows
    });
  } catch (error) {
    console.error('Get children error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// GET /api/parent/children/:studentId/attendance
// Returns attendance history for a specific child
const getChildAttendance = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { studentId } = req.params;

    // Get the parent record for this user
    const parentResult = await pool.query(
      `SELECT id FROM parents WHERE user_id = $1`,
      [userId]
    );

    if (parentResult.rows.length === 0) {
      return res.status(404).json({
        message: 'Parent profile not found.'
      });
    }

    const parentId = parentResult.rows[0].id;

    // Verify this student actually belongs to this parent
    const studentResult = await pool.query(
      `SELECT id FROM students WHERE id = $1 AND parent_id = $2`,
      [studentId, parentId]
    );

    if (studentResult.rows.length === 0) {
      return res.status(403).json({
        message: 'You are not authorized to view this student.'
      });
    }

    // Get attendance history for this student
    const attendanceResult = await pool.query(
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
    JOIN students s ON s.user_id = a.user_id
    WHERE s.id = $1
    ORDER BY a.attendance_date DESC, a.time_in DESC
    `,
    [studentId]
    );

    return res.json({
      attendance: attendanceResult.rows
    });
  } catch (error) {
    console.error('Get child attendance error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

module.exports = {
  getChildren,
  getChildAttendance
};