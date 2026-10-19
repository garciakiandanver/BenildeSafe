const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const pool = require('../config/database');
const {
  assertEmailConfigured,
  sendPasswordResetCode
} = require('../services/emailService');

const login = async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        message: 'Email and password are required.'
      });
    }

    const result = await pool.query(
      `
      SELECT
        u.id,
        u.email,
        u.status,
        u.email_verified,
        u.password_hash,
        r.name AS role,
        u.profile_photo,
        u.must_change_password,
        COALESCE(
          NULLIF(BTRIM(s.first_name), ''),
          NULLIF(BTRIM(t.first_name), ''),
          NULLIF(BTRIM(p.first_name), '')
        ) AS first_name,
        COALESCE(
          NULLIF(BTRIM(CONCAT_WS(
            ' ',
            NULLIF(BTRIM(s.first_name), ''),
            NULLIF(BTRIM(s.middle_name), ''),
            NULLIF(BTRIM(s.last_name), '')
          )), ''),
          NULLIF(BTRIM(CONCAT_WS(
            ' ',
            NULLIF(BTRIM(t.first_name), ''),
            NULLIF(BTRIM(t.middle_name), ''),
            NULLIF(BTRIM(t.last_name), '')
          )), ''),
          NULLIF(BTRIM(CONCAT_WS(
            ' ',
            NULLIF(BTRIM(p.first_name), ''),
            NULLIF(BTRIM(p.middle_name), ''),
            NULLIF(BTRIM(p.last_name), '')
          )), '')
        ) AS full_name
      FROM users u
      LEFT JOIN user_roles ur ON ur.user_id = u.id
      LEFT JOIN roles r ON r.id = ur.role_id
      LEFT JOIN students s ON s.user_id = u.id
      LEFT JOIN teachers t ON t.user_id = u.id
      LEFT JOIN parents p ON p.user_id = u.id
      WHERE u.email = $1
      `,
      [email]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({
        message: 'Invalid email or password.'
      });
    }

    const user = result.rows[0];

    if (user.status !== 'active') {
      return res.status(403).json({
        message: 'Your account is not active.'
      });
    }

    if (!user.email_verified) {
      return res.status(403).json({
        message: 'Please verify your email first.'
      });
    }

    const passwordMatch = await bcrypt.compare(
      password,
      user.password_hash
    );

    if (!passwordMatch) {
      return res.status(401).json({
        message: 'Invalid email or password.'
      });
    }

    const token = jwt.sign(
      {
        userId: user.id,
        email: user.email,
        role: user.role
      },
      process.env.JWT_SECRET,
      {
        expiresIn: '1d'
      }
    );

    return res.json({
      message: 'Login successful.',
      token,
      user: {
        id: user.id,
        email: user.email,
        role: user.role,
        full_name: user.full_name,
        first_name: user.first_name,
        profile_photo: user.profile_photo,
        must_change_password: user.must_change_password === true
      }
    });

  } catch (error) {
    console.error('Login error:', error);

    return res.status(500).json({
      message: 'Internal server error.'
    });
  }
};

const createPasswordResetCodeHash = (code) => crypto
  .createHmac('sha256', process.env.JWT_SECRET)
  .update(code)
  .digest('hex');

const requestPasswordReset = async (req, res) => {
  try {
    const email = String(req.body.email ?? '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return res.status(400).json({ message: 'Enter a valid email address.' });
    }

    assertEmailConfigured();

    const result = await pool.query(
      `
      SELECT id
      FROM users
      WHERE LOWER(email) = $1
        AND status = 'active'
        AND email_verified = TRUE
      `,
      [email]
    );

    if (result.rows.length > 0) {
      const userId = result.rows[0].id;
      const code = crypto.randomInt(100000, 1000000).toString();
      const tokenHash = createPasswordResetCodeHash(code);
      const resetRequest = await pool.query(
        `
        INSERT INTO password_reset_tokens (
          user_id, token_hash, expires_at, attempts, created_at, used_at
        )
        VALUES ($1, $2, CURRENT_TIMESTAMP + INTERVAL '15 minutes', 0, CURRENT_TIMESTAMP, NULL)
        ON CONFLICT (user_id) DO UPDATE SET
          token_hash = EXCLUDED.token_hash,
          expires_at = EXCLUDED.expires_at,
          attempts = 0,
          created_at = EXCLUDED.created_at,
          used_at = NULL
        WHERE password_reset_tokens.created_at <=
          CURRENT_TIMESTAMP - INTERVAL '1 minute'
        RETURNING user_id
        `,
        [userId, tokenHash]
      );

      if (resetRequest.rows.length > 0) {
        try {
          await sendPasswordResetCode(email, code);
        } catch (error) {
          await pool.query(
            'DELETE FROM password_reset_tokens WHERE user_id = $1 AND token_hash = $2',
            [userId, tokenHash]
          );
          throw error;
        }
      }
    }

    return res.json({
      message: 'If an active account uses this email, a reset code will be sent.'
    });
  } catch (error) {
    console.error('Request password reset error:', error);
    if (error.message?.startsWith('Email delivery is not configured.')) {
      return res.status(503).json({
        message: 'Password reset email is not configured. Please contact the administrator.'
      });
    }
    return res.status(500).json({
      message: 'Could not send a password reset code. Please try again later.'
    });
  }
};

const resetPassword = async (req, res) => {
  const email = String(req.body.email ?? '').trim().toLowerCase();
  const code = String(req.body.code ?? '').trim();
  const password = req.body.password;
  if (
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
    !/^\d{6}$/.test(code) ||
    typeof password !== 'string' ||
    password.length < 8 ||
    !/[A-Z]/.test(password) ||
    !/\d/.test(password)
  ) {
    return res.status(400).json({
      message: 'Enter a valid email and reset code. The password must be at least 8 characters and contain an uppercase letter and a number.'
    });
  }

  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    const result = await client.query(
      `
      SELECT u.id, prt.token_hash, prt.expires_at, prt.attempts, prt.used_at,
             (prt.expires_at <= CURRENT_TIMESTAMP) AS is_expired
      FROM users u
      JOIN password_reset_tokens prt ON prt.user_id = u.id
      WHERE LOWER(u.email) = $1
        AND u.status = 'active'
        AND u.email_verified = TRUE
      FOR UPDATE OF prt
      `,
      [email]
    );
    const reset = result.rows[0];
    if (
      !reset ||
      reset.used_at ||
      reset.is_expired ||
      reset.attempts >= 5
    ) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Invalid or expired reset code.' });
    }

    await client.query(
      'UPDATE password_reset_tokens SET attempts = attempts + 1 WHERE user_id = $1',
      [reset.id]
    );

    const storedHash = Buffer.from(reset.token_hash.trim(), 'hex');
    const submittedHash = Buffer.from(createPasswordResetCodeHash(code), 'hex');
    if (
      storedHash.length !== submittedHash.length ||
      !crypto.timingSafeEqual(storedHash, submittedHash)
    ) {
      await client.query('COMMIT');
      return res.status(400).json({ message: 'Invalid or expired reset code.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    await client.query(
      `UPDATE users
       SET password_hash = $1, must_change_password = FALSE,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $2`,
      [passwordHash, reset.id]
    );
    await client.query(
      'UPDATE password_reset_tokens SET used_at = CURRENT_TIMESTAMP WHERE user_id = $1',
      [reset.id]
    );
    await client.query('COMMIT');
    return res.json({ message: 'Your password has been reset. You can now log in.' });
  } catch (error) {
    if (client) await client.query('ROLLBACK').catch(() => {});
    console.error('Reset password error:', error);
    return res.status(500).json({ message: 'Could not reset your password.' });
  } finally {
    client?.release();
  }
};

const PASSWORD_RULES_MESSAGE =
  'The new password must be at least 8 characters and contain an uppercase letter and a number.';

// POST /api/auth/change-password  (signed-in user)
// Body: { current_password, new_password }
const changePassword = async (req, res) => {
  try {
    const currentPassword = req.body.current_password;
    const newPassword = req.body.new_password;

    if (typeof currentPassword !== 'string' || currentPassword.length === 0) {
      return res.status(400).json({ message: 'Enter your current password.' });
    }
    if (
      typeof newPassword !== 'string' ||
      newPassword.length < 8 ||
      !/[A-Z]/.test(newPassword) ||
      !/\d/.test(newPassword)
    ) {
      return res.status(400).json({ message: PASSWORD_RULES_MESSAGE });
    }
    if (newPassword === currentPassword) {
      return res.status(400).json({
        message: 'Your new password must be different from your current password.'
      });
    }

    const result = await pool.query(
      'SELECT password_hash FROM users WHERE id = $1',
      [req.user.userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Account not found.' });
    }

    const matches = await bcrypt.compare(
      currentPassword,
      result.rows[0].password_hash
    );
    if (!matches) {
      return res.status(400).json({ message: 'Your current password is incorrect.' });
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);
    await pool.query(
      `UPDATE users
       SET password_hash = $1, must_change_password = FALSE,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $2`,
      [passwordHash, req.user.userId]
    );

    return res.json({ message: 'Your password has been changed.' });
  } catch (error) {
    console.error('Change password error:', error);
    return res.status(500).json({ message: 'Could not change your password.' });
  }
};

module.exports = {
  login,
  requestPasswordReset,
  resetPassword,
  changePassword
};