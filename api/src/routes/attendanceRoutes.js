const express = require('express');
const {
  detectCampus,
  checkIn,
  checkOut,
  updateLocation,
  getActiveAttendance,
  getAttendanceHistory
} = require('../controllers/attendanceController');

const {
  getTodayPhotoStatus,
  startPhoto,
  submitPhoto
} = require('../controllers/photoVerificationController');

const authMiddleware = require('../middleware/authMiddleware');

const router = express.Router();

router.post('/detect-campus', authMiddleware, detectCampus);
router.post('/check-in', authMiddleware, checkIn);
router.post('/check-out', authMiddleware, checkOut);
router.post('/location', authMiddleware, updateLocation);
router.get('/active', authMiddleware, getActiveAttendance);
router.get('/history', authMiddleware, getAttendanceHistory);
router.get('/photo/today', authMiddleware, getTodayPhotoStatus);
router.post('/photo/start', authMiddleware, startPhoto);
router.post('/photo', authMiddleware, submitPhoto);

module.exports = router;
