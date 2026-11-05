const crypto = require('crypto');

// One phone per student account, and one student account per phone.
// Parents, teachers and administrators are not bound, so a parent and a
// student can use the same phone.
const MESSAGES = {
  DEVICE_REQUIRED:
    'This app version cannot be used by students. Please install the latest BenildeSafe update.',
  DEVICE_MISMATCH:
    'This account is already linked to another phone. A student account can be used on one phone only. Ask the school to reset the linked phone.',
  DEVICE_IN_USE:
    'This phone is already used by another student account. Only one student account can be used on a phone. Ask the school if this is a mistake.'
};

const validDeviceId = (value) => {
  const id = String(value ?? '').trim();
  return id.length >= 16 && id.length <= 100 ? id : null;
};

const newSessionId = () => crypto.randomBytes(16).toString('hex');

// Links the account to the phone on first login, and starts a new login
// session (which ends any older one). Returns { sid } or { code, message }.
const claimDevice = async (pool, userId, deviceId) => {
  const sid = newSessionId();

  const refresh = async () => {
    const existing = await pool.query(
      'SELECT device_id FROM student_devices WHERE user_id = $1',
      [userId]
    );
    if (existing.rowCount === 0) return null;
    if (existing.rows[0].device_id !== deviceId) {
      return { code: 'DEVICE_MISMATCH', message: MESSAGES.DEVICE_MISMATCH };
    }
    await pool.query(
      `UPDATE student_devices
       SET session_id = $2, last_login_at = CURRENT_TIMESTAMP
       WHERE user_id = $1`,
      [userId, sid]
    );
    return { sid };
  };

  const known = await refresh();
  if (known) return known;

  const inserted = await pool.query(
    `INSERT INTO student_devices (user_id, device_id, session_id)
     VALUES ($1, $2, $3)
     ON CONFLICT DO NOTHING
     RETURNING user_id`,
    [userId, deviceId, sid]
  );
  if (inserted.rowCount > 0) return { sid };

  // Nothing was inserted: either this account was linked a moment ago by a
  // second request, or another student account already uses this phone.
  const again = await refresh();
  if (again) return again;
  return { code: 'DEVICE_IN_USE', message: MESSAGES.DEVICE_IN_USE };
};

// True while the token's session is the account's latest login.
const sessionIsCurrent = async (pool, userId, sid) => {
  if (!sid) return false;
  const row = await pool.query(
    'SELECT session_id FROM student_devices WHERE user_id = $1',
    [userId]
  );
  return row.rowCount > 0 && row.rows[0].session_id === sid;
};

module.exports = { MESSAGES, validDeviceId, claimDevice, sessionIsCurrent };
