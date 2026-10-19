const pool = require('../config/database');

// Only these roles have a personal record with a name.
// (Table names come from this fixed map, never from user input.)
const ROLE_TABLES = {
  student: 'students',
  teacher: 'teachers',
  parent: 'parents'
};

const NAME_PATTERN = /^[\p{L}\p{M}][\p{L}\p{M}\s.'-]*$/u;
const PHOTO_PATTERN = /^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/]+={0,2})$/;
const MAX_PHOTO_BYTES = 400 * 1024; // decoded size

const roleOf = (req) => String(req.user?.role ?? '').toLowerCase();

const loadProfile = async (userId, role) => {
  const userResult = await pool.query(
    'SELECT id, email, profile_photo FROM users WHERE id = $1',
    [userId]
  );
  if (userResult.rowCount === 0) return null;

  const clean = (value) => (value == null ? '' : String(value).trim());

  // SELECT * so a differently named column can never break the profile.
  let record = {};
  const table = ROLE_TABLES[role];
  if (table) {
    const recordResult = await pool.query(
      `SELECT * FROM ${table} WHERE user_id = $1`,
      [userId]
    );
    record = recordResult.rows[0] ?? {};
  }

  const names = {
    first_name: clean(record.first_name),
    middle_name: clean(record.middle_name),
    last_name: clean(record.last_name)
  };

  // Read-only details that depend on the role.
  const details = {};
  if (role === 'student') {
    details.student_number = clean(record.student_number);
    details.course = clean(record.course);
    details.year_level = clean(record.year_level);
    details.section = clean(record.section);
  } else if (role === 'teacher') {
    details.employee_number = clean(
      record.employee_number ??
        record.employee_id ??
        record.employee_no ??
        record.employee_code
    );
  }

  const fullName = [names.first_name, names.middle_name, names.last_name]
    .filter(Boolean)
    .join(' ');

  return {
    id: userResult.rows[0].id,
    email: userResult.rows[0].email,
    role,
    ...names,
    ...details,
    full_name: fullName,
    profile_photo: userResult.rows[0].profile_photo
  };
};

// GET /api/profile
const getProfile = async (req, res) => {
  try {
    const profile = await loadProfile(req.user.userId, roleOf(req));
    if (!profile) {
      return res.status(404).json({ message: 'Account not found.' });
    }
    return res.json({ user: profile });
  } catch (error) {
    console.error('Get profile error:', error);
    return res.status(500).json({ message: 'Could not load your profile.' });
  }
};

const cleanName = (value) => String(value ?? '').trim().replace(/\s+/g, ' ');

// PUT /api/profile   Body: { first_name, middle_name, last_name }
const updateProfile = async (req, res) => {
  try {
    const role = roleOf(req);
    const table = ROLE_TABLES[role];
    if (!table) {
      return res.status(400).json({
        message: 'This account does not have an editable name.'
      });
    }

    const firstName = cleanName(req.body.first_name);
    const middleName = cleanName(req.body.middle_name);
    const lastName = cleanName(req.body.last_name);

    if (!firstName || !lastName) {
      return res.status(400).json({
        message: 'First name and last name are required.'
      });
    }
    for (const [label, value, required] of [
      ['First name', firstName, true],
      ['Middle name', middleName, false],
      ['Last name', lastName, true]
    ]) {
      if (!value && !required) continue;
      if (value.length > 60 || !NAME_PATTERN.test(value)) {
        return res.status(400).json({
          message: `${label} can only contain letters, spaces, apostrophes, periods and hyphens (max 60 characters).`
        });
      }
    }

    const result = await pool.query(
      `UPDATE ${table}
       SET first_name = $1, middle_name = $2, last_name = $3
       WHERE user_id = $4`,
      [firstName, middleName, lastName, req.user.userId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Profile record not found.' });
    }

    const profile = await loadProfile(req.user.userId, role);
    return res.json({ message: 'Profile updated.', user: profile });
  } catch (error) {
    console.error('Update profile error:', error);
    return res.status(500).json({ message: 'Could not update your profile.' });
  }
};

// PUT /api/profile/photo   Body: { photo: "data:image/jpeg;base64,...." }
const uploadPhoto = async (req, res) => {
  try {
    const photo = req.body.photo;
    const match = typeof photo === 'string' ? PHOTO_PATTERN.exec(photo) : null;
    if (!match) {
      return res.status(400).json({
        message: 'Please choose a JPG, PNG or WebP image.'
      });
    }

    const base64 = match[2];
    const decodedBytes = Math.floor((base64.length * 3) / 4);
    if (decodedBytes > MAX_PHOTO_BYTES) {
      return res.status(400).json({
        message: 'That photo is too large. Please choose a smaller one.'
      });
    }

    await pool.query(
      'UPDATE users SET profile_photo = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
      [photo, req.user.userId]
    );
    return res.json({ message: 'Profile photo updated.', profile_photo: photo });
  } catch (error) {
    console.error('Upload photo error:', error);
    return res.status(500).json({ message: 'Could not save your photo.' });
  }
};

// DELETE /api/profile/photo
const deletePhoto = async (req, res) => {
  try {
    await pool.query(
      'UPDATE users SET profile_photo = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = $1',
      [req.user.userId]
    );
    return res.json({ message: 'Profile photo removed.', profile_photo: null });
  } catch (error) {
    console.error('Delete photo error:', error);
    return res.status(500).json({ message: 'Could not remove your photo.' });
  }
};

module.exports = { getProfile, updateProfile, uploadPhoto, deletePhoto };