const express = require('express');
const multer = require('multer');
const authenticateToken = require('../middleware/authMiddleware');
const {
  getCourses,
  addCourse,
  updateCourse,
  deleteCourse,
  getDepartments,
  addDepartment,
  updateDepartment,
  deleteDepartment,
  getClassSchedules,
  getAcademicTerms,
  createAcademicTerm,
  updateAcademicTerm,
  updateClassSchedule,
  deleteClassSchedule,
  archiveCourseTermSchedules,
  importClassSchedules
} = require('../controllers/classScheduleController');

const router = express.Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 1 }
});

const requireAdmin = (req, res, next) => {
  if (req.user.role?.toLowerCase() !== 'admin') {
    return res.status(403).json({
      message: 'Administrator access is required.'
    });
  }
  return next();
};

const handleScheduleFile = (req, res, next) => {
  upload.single('schedule')(req, res, (error) => {
    if (error) {
      return res.status(400).json({
        message: error.code === 'LIMIT_FILE_SIZE'
          ? 'Schedule file must be 5 MB or smaller.'
          : 'Could not process the uploaded schedule file.'
      });
    }
    return next();
  });
};

router.use(authenticateToken, requireAdmin);
router.get('/terms', getAcademicTerms);
router.post('/terms', createAcademicTerm);
router.put('/terms/:termId', updateAcademicTerm);
router.get('/departments', getDepartments);
router.post('/departments', addDepartment);
router.put('/departments/:departmentId', updateDepartment);
router.delete('/departments/:departmentId', deleteDepartment);
router.get('/courses', getCourses);
router.post('/courses', addCourse);
router.put('/courses/:courseCode', updateCourse);
router.delete('/courses/:courseCode', deleteCourse);
router.get('/', getClassSchedules);
router.get('/:courseCode/schedules', getClassSchedules);
router.post('/:courseCode/archive', archiveCourseTermSchedules);
router.put('/:scheduleId', updateClassSchedule);
router.delete('/:scheduleId', deleteClassSchedule);
router.post('/import', handleScheduleFile, importClassSchedules);
router.post('/:courseCode/import', handleScheduleFile, importClassSchedules);

module.exports = router;