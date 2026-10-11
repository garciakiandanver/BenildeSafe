const express = require('express');
const authenticateToken = require('../middleware/authMiddleware');
const { getClassAttendance } = require('../controllers/teacherPortalController');

const router = express.Router();

router.use(authenticateToken);
router.get('/class-attendance', getClassAttendance);

module.exports = router;