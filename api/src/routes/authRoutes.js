const express = require('express');
const {
  login,
  requestPasswordReset,
  resetPassword,
  changePassword
} = require('../controllers/authController');
const authenticateToken = require('../middleware/authMiddleware');

const router = express.Router();

router.post('/login', login);
router.post('/forgot-password', requestPasswordReset);
router.post('/reset-password', resetPassword);
router.post('/change-password', authenticateToken, changePassword);

router.get('/me', authenticateToken, (req, res) => {
  res.json({
    message: 'Authentication successful.',
    user: req.user
  });
});

module.exports = router;