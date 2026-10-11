const pool = require('../config/database');
const bcrypt = require('bcrypt');
const { sendRegistrationDecision } = require('../services/emailService');

// POST /api/auth/register
const register = async (req, res) => {
  try {
    const {
      email,
      password,
      first_name,
      middle_name,
      last_name,
      requested_role_id,
      student_number,
      course,
      year_level,
      section,
      employee_number,
      contact_number,
      child_student_number,
    } = req.body;

    // Basic validation
    if (!email || !password || !first_name || !last_name || !requested_role_id) {
      return res.status(400).json({
        message: 'Email, password, name, and role are required.'
      });
    }

    // Check if email already exists in users table
    const existingUser = await pool.query(
      `SELECT id FROM users WHERE email = $1`,
      [email]
    );

    if (existingUser.rows.length > 0) {
      return res.status(400).json({
        message: 'Email is already registered.'
      });
    }

    // Check if email already has a pending request
    const existingRequest = await pool.query(
      `SELECT id FROM registration_requests WHERE email = $1 AND status = 'pending'`,
      [email]
    );

    if (existingRequest.rows.length > 0) {
      return res.status(400).json({
        message: 'A registration request with this email is already pending.'
      });
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // Insert registration request
    await pool.query(
      `
      INSERT INTO registration_requests (
        id, email, password_hash, first_name, middle_name, last_name,
        requested_role_id, student_number, course, year_level, section,
        employee_number, contact_number, child_student_number,
        status, email_verified, requested_at
      ) VALUES (
        gen_random_uuid(), $1, $2, $3, $4, $5,
        $6, $7, $8, $9, $10,
        $11, $12, $13,
        'pending', true, NOW()
      )
      `,
      [
        email, passwordHash, first_name, middle_name || null, last_name,
        requested_role_id, student_number || null, course || null,
        year_level || null, section || null,
        employee_number || null, contact_number || null,
        child_student_number || null,
      ]
    );

    return res.status(201).json({
      message: 'Registration request submitted successfully. Please wait for admin approval.'
    });
  } catch (error) {
    console.error('Register error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// GET /api/admin/registration-requests
const getRegistrationRequests = async (req, res) => {
  try {
    const result = await pool.query(
      `
      SELECT
        rr.id,
        rr.email,
        rr.first_name,
        rr.middle_name,
        rr.last_name,
        rr.requested_role_id,
        rr.student_number,
        rr.course,
        rr.year_level,
        rr.section,
        rr.employee_number,
        rr.contact_number,
        rr.child_student_number,
        rr.status,
        rr.requested_at,
        r.name AS role_name
      FROM registration_requests rr
      LEFT JOIN roles r ON r.id = rr.requested_role_id
      ORDER BY rr.requested_at DESC
      `
    );

    return res.json({ requests: result.rows });
  } catch (error) {
    console.error('Get registration requests error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

// PUT /api/admin/registration-requests/:id/approve
const approveRequest = async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { id } = req.params;
    const adminId = req.user.userId;

    // Get the request
    const requestResult = await client.query(
      `
      SELECT rr.*, r.name AS role_name
      FROM registration_requests rr
      LEFT JOIN roles r ON r.id = rr.requested_role_id
      WHERE rr.id = $1 AND rr.status = 'pending'
      FOR UPDATE OF rr
      `,
      [id]
    );

    if (requestResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        message: 'Registration request not found or already processed.'
      });
    }

    const request = requestResult.rows[0];

    // Check email not already taken
    const existingUser = await client.query(
      `SELECT id FROM users WHERE email = $1`,
      [request.email]
    );

    if (existingUser.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        message: 'Email is already registered as a user.'
      });
    }

    // Create user
    const userResult = await client.query(
      `
      INSERT INTO users (id, email, password_hash, status, email_verified)
      VALUES (gen_random_uuid(), $1, $2, 'active', true)
      RETURNING id
      `,
      [request.email, request.password_hash]
    );

    const userId = userResult.rows[0].id;

    // Assign role
    await client.query(
      `INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2)`,
      [userId, request.requested_role_id]
    );

    // Create profile based on role
    // Role IDs: 1=Admin, 2=Student, 3=Teacher, 4=Parent
    if (request.requested_role_id === 2) {
      // Student
      await client.query(
        `
        INSERT INTO students (id, user_id, student_number, first_name, middle_name, last_name, course, year_level, section)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8)
        `,
        [
          userId, request.student_number, request.first_name,
          request.middle_name, request.last_name, request.course,
          request.year_level, request.section
        ]
      );
    } else if (request.requested_role_id === 3) {
      // Teacher
      await client.query(
        `
        INSERT INTO teachers (id, user_id, employee_number, first_name, middle_name, last_name)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, $5)
        `,
        [
          userId, request.employee_number, request.first_name,
          request.middle_name, request.last_name
        ]
      );
    } else if (request.requested_role_id === 4) {
      // Parent
      const parentResult = await client.query(
        `
        INSERT INTO parents (id, user_id, first_name, middle_name, last_name, contact_number)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, $5)
        RETURNING id
        `,
        [
          userId, request.first_name, request.middle_name,
          request.last_name, request.contact_number
        ]
      );

      // Link child if student number provided
      if (request.child_student_number) {
        const parentId = parentResult.rows[0].id;
        await client.query(
          `
          UPDATE students SET parent_id = $1
          WHERE UPPER(BTRIM(student_number)) = UPPER(BTRIM($2))
            AND parent_id IS NULL
          `,
          [parentId, request.child_student_number]
        );
      }
    }

    // Update request status
    await client.query(
      `
      UPDATE registration_requests
      SET status = 'approved', reviewed_at = NOW(), reviewed_by = $1
      WHERE id = $2
      `,
      [adminId, id]
    );

    await client.query('COMMIT');

    try {
      await sendRegistrationDecision({
        email: request.email,
        fullName: [request.first_name, request.middle_name, request.last_name]
          .filter(Boolean)
          .join(' '),
        role: request.role_name,
        approved: true
      });
    } catch (error) {
      console.error('Approve request notification email error:', error);
      return res.json({
        message: 'Request approved and account created, but the notification email could not be sent.',
        notificationEmailSent: false
      });
    }

    return res.json({
      message: 'Registration request approved. Account created and notification email sent.',
      notificationEmailSent: true
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Approve request error:', error);

    // Handle duplicate key errors
    if (error.code === '23505') {
      if (error.constraint === 'students_student_number_key') {
        return res.status(400).json({
          message: 'Student number already exists. Cannot approve this request.'
        });
      }
      if (error.constraint === 'users_email_key') {
        return res.status(400).json({
          message: 'Email is already registered. Cannot approve this request.'
        });
      }
      return res.status(400).json({
        message: 'Duplicate data found. Cannot approve this request.'
      });
    }

    return res.status(500).json({
      message: 'Internal server error.'
    });
  } finally {
    client.release();
  }
};

// PUT /api/admin/registration-requests/:id/reject
const rejectRequest = async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const adminId = req.user.userId;

    await client.query('BEGIN');
    const result = await client.query(
      `
      SELECT rr.*, r.name AS role_name
      FROM registration_requests rr
      LEFT JOIN roles r ON r.id = rr.requested_role_id
      WHERE rr.id = $1 AND rr.status = 'pending'
      FOR UPDATE OF rr
      `,
      [id]
    );

    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        message: 'Registration request not found or already processed.'
      });
    }

    const request = result.rows[0];
    await client.query(
      `
      UPDATE registration_requests
      SET status = 'rejected', reviewed_at = NOW(), reviewed_by = $1
      WHERE id = $2
      `,
      [adminId, id]
    );

    await client.query('COMMIT');

    try {
      await sendRegistrationDecision({
        email: request.email,
        fullName: [request.first_name, request.middle_name, request.last_name]
          .filter(Boolean)
          .join(' '),
        role: request.role_name,
        approved: false
      });
    } catch (error) {
      console.error('Reject request notification email error:', error);
      return res.json({
        message: 'Request declined, but the notification email could not be sent.',
        notificationEmailSent: false
      });
    }

    return res.json({
      message: 'Registration request declined and notification email sent.',
      notificationEmailSent: true
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Reject request error:', error);
    return res.status(500).json({
      message: 'Internal server error.'
    });
  } finally {
    client.release();
  }
};

module.exports = {
  register,
  getRegistrationRequests,
  approveRequest,
  rejectRequest,
};