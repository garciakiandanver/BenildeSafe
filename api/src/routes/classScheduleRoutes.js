const express = require('express');
const authenticateToken = require('../middleware/authMiddleware');
const {
  getCourses,
  addCourse,
  updateCourse,
  deleteCourse,
  getDepartments,
  addDepartment,
  updateDepartment,
  deleteDepartment
} = require('../controllers/classScheduleController');

// Only courses and departments are managed here now. Class schedules and the
// timetable upload were removed from the system.
const router = express.Router();

const requireAdmin = (req, res, next) => {
  if (req.user.role?.toLowerCase() !== 'admin') {
    return res.status(403).json({
      message: 'Administrator access is required.'
    });
  }
  return next();
};

router.use(authenticateToken, requireAdmin);
router.get('/departments', getDepartments);
router.post('/departments', addDepartment);
router.put('/departments/:departmentId', updateDepartment);
router.delete('/departments/:departmentId', deleteDepartment);
router.get('/courses', getCourses);
router.post('/courses', addCourse);
router.put('/courses/:courseCode', updateCourse);
router.delete('/courses/:courseCode', deleteCourse);

module.exports = router;
