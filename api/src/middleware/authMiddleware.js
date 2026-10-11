const jwt = require('jsonwebtoken');
const pool = require('../config/database');

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
      'SELECT status FROM users WHERE id = $1',
      [decoded.userId]
    );
    if (account.rowCount === 0 || account.rows[0].status !== 'active') {
      return res.status(403).json({
        message: 'This account is inactive.'
      });
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