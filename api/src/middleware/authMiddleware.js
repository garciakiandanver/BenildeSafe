const jwt = require('jsonwebtoken');
const pool = require('../config/database');

// While a user still has a temporary password, only these calls are allowed.
const ALLOWED_WHEN_PASSWORD_CHANGE_REQUIRED = [
  '/api/auth/change-password',
  '/api/auth/me'
];

const authenticateToken = async (req, res, next) => {
  const authHeader = req.headers.authorization;

  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({
      message: 'Access token is required.'
    });
  }

  let decoded;
  try {
    decoded = jwt.verify(token, process.env.JWT_SECRET);
  } catch (error) {
    return res.status(403).json({
      message: 'Invalid or expired token.'
    });
  }

  try {
    const account = await pool.query(
      'SELECT status, must_change_password FROM users WHERE id = $1',
      [decoded.userId]
    );
    if (account.rowCount === 0 || account.rows[0].status !== 'active') {
      return res.status(403).json({
        message: 'This account is inactive.'
      });
    }

    if (account.rows[0].must_change_password === true) {
      const path = String(req.originalUrl ?? '')
        .split('?')[0]
        .replace(/\/+$/, '');
      if (!ALLOWED_WHEN_PASSWORD_CHANGE_REQUIRED.includes(path)) {
        return res.status(403).json({
          code: 'PASSWORD_CHANGE_REQUIRED',
          message: 'Please change your temporary password first.'
        });
      }
    }

    req.user = decoded;

    return next();
  } catch (error) {
    console.error('Authenticate token error:', error);
    return res.status(500).json({
      message: 'Could not verify the account status.'
    });
  }
};

module.exports = authenticateToken;