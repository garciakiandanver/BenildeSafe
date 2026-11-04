const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/authMiddleware');
const {
  getSummary,
  getStudents,
  getTeachers,
  addTeacher,
  getParents,
  linkParentChild,
  unlinkParentChild,
  updateManagedUser,
  setManagedUserStatus,
  getCampuses,
  updateCampusBoundary,
  addCampus,
  deleteCampus,
  getAttendance,
  getAttendanceTrend,
  correctAttendance,
  getReportUsers,
  getUserAttendanceReport,
} = require('../controllers/adminController');

// Self-registration was removed. Accounts are created by the school: students
// and parents from the registrar's master list through the bulk importer,
// teachers one at a time through POST /teachers below. The parent child-link
// requests are a different thing and still live in their own routes.

const requireAdmin = (req, res, next) => {
  if (req.user.role?.toLowerCase() !== 'admin') {
    return res.status(403).json({
      message: 'Administrator access is required.'
    });
  }
  return next();
};

router.get('/summary', authenticateToken, requireAdmin, getSummary);
router.get('/students', authenticateToken, requireAdmin, getStudents);
router.get('/teachers', authenticateToken, requireAdmin, getTeachers);
router.post('/teachers', authenticateToken, requireAdmin, addTeacher);
router.get('/parents', authenticateToken, requireAdmin, getParents);
router.post('/parents/:parentId/children', authenticateToken, requireAdmin, linkParentChild);
router.delete(
  '/parents/:parentId/children/:studentId',
  authenticateToken,
  requireAdmin,
  unlinkParentChild
);
router.put('/users/:userId', authenticateToken, requireAdmin, updateManagedUser);
router.patch('/users/:userId/status', authenticateToken, requireAdmin, setManagedUserStatus);
router.get('/campuses', authenticateToken, getCampuses);
router.post('/campuses', authenticateToken, requireAdmin, addCampus);
router.put('/campuses/:id/boundary', authenticateToken, requireAdmin, updateCampusBoundary);
router.delete('/campuses/:id', authenticateToken, requireAdmin, deleteCampus);
router.get('/attendance', authenticateToken, requireAdmin, getAttendance);
router.get('/attendance/trend', authenticateToken, requireAdmin, getAttendanceTrend);
router.put('/attendance/:id', authenticateToken, requireAdmin, correctAttendance);
router.get('/report/users', authenticateToken, requireAdmin, getReportUsers);
router.get(
  '/report/users/:userId',
  authenticateToken,
  requireAdmin,
  getUserAttendanceReport
);

module.exports = router;
