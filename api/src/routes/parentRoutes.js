const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/authMiddleware');
const {
  getChildren,
  getChildAttendance
} = require('../controllers/parentController');

router.get('/children', authenticateToken, getChildren);
router.get('/children/:studentId/attendance', authenticateToken, getChildAttendance);

module.exports = router;