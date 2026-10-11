const pool = require('../config/database');

const SETUP_MESSAGE =
  'The database is missing the child link setup. Run the child link SQL in pgAdmin, then restart the API.';

const hasRole = (req, role) => req.user?.role?.toLowerCase() === role;

const fullName = (first, middle, last) =>
  [first, middle, last]
    .map((part) => String(part ?? '').trim())
    .filter(Boolean)
    .join(' ');

// In-app notification of type 'System' (the notifications table only allows
// 'Attendance', 'Reminder' and 'System'). The specific event is kept in metadata.
const notifyUsers = async (userIds, title, message, metadata) => {
  const ids = [...new Set(userIds.filter(Boolean))];
  if (ids.length === 0) return;
  await pool.query(
    `
    INSERT INTO notifications (user_id, type, title, message, metadata)
    SELECT u, 'System', $2, $3, $4::jsonb
    FROM unnest($1::uuid[]) AS u
    `,
    [ids, title, message, JSON.stringify(metadata)]
  );
};

// ---------------------------------------------------------------- parent side

// POST /api/child-links   { student_number }
// The parent asks to link another child. The admin must approve it.
const createChildLinkRequest = async (req, res) => {
  try {
    if (!hasRole(req, 'parent')) {
      return res.status(403).json({
        message: 'Only parents can request to link a child.'
      });
    }

    const studentNumber = String(req.body.student_number ?? '').trim();
    if (!studentNumber) {
      return res.status(400).json({
        message: "Enter your child's student number."
      });
    }
    if (studentNumber.length > 40) {
      return res.status(400).json({ message: 'That student number is too long.' });
    }

    const parentResult = await pool.query(
      `
      SELECT id, first_name, middle_name, last_name
      FROM parents
      WHERE user_id = $1
      `,
      [req.user.userId]
    );
    if (parentResult.rows.length === 0) {
      return res.status(404).json({ message: 'Parent profile not found.' });
    }
    const parent = parentResult.rows[0];

    const studentResult = await pool.query(
      `
      SELECT id, parent_id, student_number, first_name, middle_name, last_name
      FROM students
      WHERE UPPER(BTRIM(student_number)) = UPPER($1)
      `,
      [studentNumber]
    );
    if (studentResult.rows.length === 0) {
      return res.status(404).json({
        message: 'No student was found with that student number. Check the number and try again.'
      });
    }
    const student = studentResult.rows[0];

    if (student.parent_id === parent.id) {
      return res.status(409).json({
        message: 'This child is already linked to your account.'
      });
    }

    const pending = await pool.query(
      `
      SELECT 1 FROM child_link_requests
      WHERE parent_id = $1 AND student_id = $2 AND status = 'pending'
      `,
      [parent.id, student.id]
    );
    if (pending.rowCount > 0) {
      return res.status(409).json({
        message: 'You already have a pending request for this student.'
      });
    }

    const inserted = await pool.query(
      `
      INSERT INTO child_link_requests (parent_id, student_id)
      VALUES ($1, $2)
      RETURNING id, status, requested_at
      `,
      [parent.id, student.id]
    );
    const request = inserted.rows[0];

    // Let the administrators know (a failure here must not undo the request).
    try {
      const admins = await pool.query(
        `
        SELECT ur.user_id
        FROM user_roles ur
        JOIN roles r ON r.id = ur.role_id
        WHERE LOWER(r.name) = 'admin'
        `
      );
      await notifyUsers(
        admins.rows.map((row) => row.user_id),
        'New child link request',
        `${fullName(parent.first_name, parent.middle_name, parent.last_name)} asked to link ${fullName(student.first_name, student.middle_name, student.last_name)} (${student.student_number}) to their account.`,
        { event: 'child_link_requested', request_id: request.id }
      );
    } catch (error) {
      console.error('Child link admin notification error:', error);
    }

    return res.status(201).json({
      message: 'Request sent. The administrator will review it.',
      request
    });
  } catch (error) {
    console.error('Create child link request error:', error);
    if (error.code === '42P01') {
      return res.status(500).json({ message: SETUP_MESSAGE });
    }
    if (error.code === '23505') {
      return res.status(409).json({
        message: 'You already have a pending request for this student.'
      });
    }
    return res.status(500).json({ message: 'Could not send the request.' });
  }
};

// GET /api/child-links/mine   (parent: my own requests, newest first)
const listMyChildLinkRequests = async (req, res) => {
  try {
    if (!hasRole(req, 'parent')) {
      return res.status(403).json({ message: 'Only parents can view their requests.' });
    }
    const result = await pool.query(
      `
      SELECT
        r.id, r.status, r.requested_at, r.reviewed_at,
        s.student_number, s.first_name, s.middle_name, s.last_name
      FROM child_link_requests r
      JOIN students s ON s.id = r.student_id
      WHERE r.parent_id = (SELECT id FROM parents WHERE user_id = $1)
      ORDER BY r.requested_at DESC
      LIMIT 50
      `,
      [req.user.userId]
    );
    return res.json({
      requests: result.rows.map((row) => ({
        id: row.id,
        status: row.status,
        requested_at: row.requested_at,
        reviewed_at: row.reviewed_at,
        student_number: row.student_number,
        student_name: fullName(row.first_name, row.middle_name, row.last_name)
      }))
    });
  } catch (error) {
    console.error('List my child link requests error:', error);
    if (error.code === '42P01') {
      return res.status(500).json({ message: SETUP_MESSAGE });
    }
    return res.status(500).json({ message: 'Could not load your requests.' });
  }
};

// ----------------------------------------------------------------- admin side

// GET /api/child-links   (admin: every request, pending first)
const listChildLinkRequests = async (req, res) => {
  try {
    if (!hasRole(req, 'admin')) {
      return res.status(403).json({ message: 'Administrator access is required.' });
    }
    const result = await pool.query(
      `
      SELECT
        r.id, r.status, r.requested_at, r.reviewed_at,
        p.first_name AS parent_first, p.middle_name AS parent_middle,
        p.last_name AS parent_last, p.contact_number,
        s.student_number, s.first_name, s.middle_name, s.last_name,
        s.course, s.year_level, s.section,
        cp.first_name AS current_first, cp.middle_name AS current_middle,
        cp.last_name AS current_last,
        (s.parent_id IS NOT NULL AND s.parent_id <> r.parent_id) AS linked_to_other,
        (s.parent_id = r.parent_id) AS already_linked
      FROM child_link_requests r
      JOIN parents p ON p.id = r.parent_id
      JOIN students s ON s.id = r.student_id
      LEFT JOIN parents cp ON cp.id = s.parent_id
      ORDER BY (r.status = 'pending') DESC, r.requested_at DESC
      LIMIT 200
      `
    );
    return res.json({
      requests: result.rows.map((row) => ({
        id: row.id,
        status: row.status,
        requested_at: row.requested_at,
        reviewed_at: row.reviewed_at,
        parent_name: fullName(row.parent_first, row.parent_middle, row.parent_last),
        parent_contact: row.contact_number,
        student_name: fullName(row.first_name, row.middle_name, row.last_name),
        student_number: row.student_number,
        course: row.course,
        year_level: row.year_level,
        section: row.section,
        already_linked: row.already_linked === true,
        current_parent_name: row.linked_to_other
          ? fullName(row.current_first, row.current_middle, row.current_last)
          : null
      }))
    });
  } catch (error) {
    console.error('List child link requests error:', error);
    if (error.code === '42P01') {
      return res.status(500).json({ message: SETUP_MESSAGE });
    }
    return res.status(500).json({ message: 'Could not load the requests.' });
  }
};

const loadPendingRequest = (client, id) =>
  client.query(
    `
    SELECT
      r.id, r.parent_id, r.student_id,
      p.user_id AS parent_user_id,
      s.parent_id AS current_parent_id,
      s.student_number, s.first_name, s.middle_name, s.last_name,
      cp.user_id AS old_parent_user_id
    FROM child_link_requests r
    JOIN parents p ON p.id = r.parent_id
    JOIN students s ON s.id = r.student_id
    LEFT JOIN parents cp ON cp.id = s.parent_id
    WHERE r.id = $1::uuid AND r.status = 'pending'
    FOR UPDATE OF r
    `,
    [id]
  );

// PUT /api/child-links/:id/approve
// Links the student to the parent. A student has one parent account, so an
// existing link to a different parent is replaced (the admin sees a warning).
const approveChildLink = async (req, res) => {
  if (!hasRole(req, 'admin')) {
    return res.status(403).json({ message: 'Administrator access is required.' });
  }
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');

    const found = await loadPendingRequest(client, req.params.id);
    if (found.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        message: 'Request not found or already processed.'
      });
    }
    const request = found.rows[0];

    await client.query('UPDATE students SET parent_id = $1 WHERE id = $2', [
      request.parent_id,
      request.student_id
    ]);
    await client.query(
      `
      UPDATE child_link_requests
      SET status = 'approved', reviewed_at = NOW(), reviewed_by = $1
      WHERE id = $2
      `,
      [req.user.userId, request.id]
    );
    await client.query('COMMIT');

    const childName = fullName(request.first_name, request.middle_name, request.last_name);
    try {
      await notifyUsers(
        [request.parent_user_id],
        'Child link approved',
        `${childName} is now linked to your account. You will receive their attendance notifications.`,
        { event: 'child_link_approved', student_id: request.student_id }
      );
      if (request.current_parent_id && request.current_parent_id !== request.parent_id) {
        await notifyUsers(
          [request.old_parent_user_id],
          'Child link changed',
          `${childName} is no longer linked to your account.`,
          { event: 'child_link_removed', student_id: request.student_id }
        );
      }
    } catch (error) {
      console.error('Child link approval notification error:', error);
    }

    return res.json({ message: `${childName} is now linked to the parent.` });
  } catch (error) {
    if (client) await client.query('ROLLBACK').catch(() => {});
    console.error('Approve child link error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The request ID is invalid.' });
    }
    return res.status(500).json({ message: 'Could not approve the request.' });
  } finally {
    client?.release();
  }
};

// PUT /api/child-links/:id/reject
const rejectChildLink = async (req, res) => {
  if (!hasRole(req, 'admin')) {
    return res.status(403).json({ message: 'Administrator access is required.' });
  }
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');

    const found = await loadPendingRequest(client, req.params.id);
    if (found.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        message: 'Request not found or already processed.'
      });
    }
    const request = found.rows[0];

    await client.query(
      `
      UPDATE child_link_requests
      SET status = 'rejected', reviewed_at = NOW(), reviewed_by = $1
      WHERE id = $2
      `,
      [req.user.userId, request.id]
    );
    await client.query('COMMIT');

    const childName = fullName(request.first_name, request.middle_name, request.last_name);
    try {
      await notifyUsers(
        [request.parent_user_id],
        'Child link declined',
        `Your request to link ${childName} was declined. Please contact the school if you think this is a mistake.`,
        { event: 'child_link_rejected', student_id: request.student_id }
      );
    } catch (error) {
      console.error('Child link rejection notification error:', error);
    }

    return res.json({ message: 'Request declined.' });
  } catch (error) {
    if (client) await client.query('ROLLBACK').catch(() => {});
    console.error('Reject child link error:', error);
    if (error.code === '22P02') {
      return res.status(400).json({ message: 'The request ID is invalid.' });
    }
    return res.status(500).json({ message: 'Could not decline the request.' });
  } finally {
    client?.release();
  }
};

module.exports = {
  createChildLinkRequest,
  listMyChildLinkRequests,
  listChildLinkRequests,
  approveChildLink,
  rejectChildLink
};