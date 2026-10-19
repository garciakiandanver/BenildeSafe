const express = require('express');
const {
  detectCampus,
  checkIn,
  getCurrentClassSchedule,
  getNextClass,
  getMyClassSchedule,
  checkOut,
  updateLocation,
  getActiveAttendance,
  getAttendanceHistory,
  getDailySchedule
} = require('../controllers/attendanceController');

const authMiddleware = require('../middleware/authMiddleware');

const router = express.Router();

router.post('/detect-campus', authMiddleware, detectCampus);
router.post('/check-in', authMiddleware, checkIn);
router.get('/current-class', authMiddleware, getCurrentClassSchedule);
router.get('/next-class', authMiddleware, getNextClass);
router.get('/daily-schedule', authMiddleware, getDailySchedule);
router.get('/my-schedule', authMiddleware, getMyClassSchedule);
router.post('/check-out', authMiddleware, checkOut);
router.post('/location', authMiddleware, updateLocation);
router.get('/active', authMiddleware, getActiveAttendance);
router.get('/history', authMiddleware, getAttendanceHistory);

module.exports = router;