const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/authMiddleware');
const {
  getSummary,
  getStudents,
  getTeachers,
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
  correctAttendance,
  getReportUsers,
  getUserAttendanceReport,
} = require('../controllers/adminController');
const {
  getRegistrationRequests,
  approveRequest,
  rejectRequest,
} = require('../controllers/registrationController');

const requireAdmin = (req, res, next) => {
  if (req.user.role?.toLowerCase() !== 'admin') {
    return res.status(403).json({
      message: 'Administrator access is required.'
    });
  }
  return next();
};

router.get('/summary', authenticateToken, getSummary);
router.get('/students', authenticateToken, getStudents);
router.get('/teachers', authenticateToken, getTeachers);
router.get('/parents', authenticateToken, getParents);
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
router.post('/campuses', authenticateToken, addCampus);
router.put('/campuses/:id/boundary', authenticateToken, updateCampusBoundary);
router.delete('/campuses/:id', authenticateToken, deleteCampus);
router.get('/attendance', authenticateToken, getAttendance);
router.put('/attendance/:id', authenticateToken, correctAttendance);
router.get('/report/users', authenticateToken, requireAdmin, getReportUsers);
router.get(
  '/report/users/:userId',
  authenticateToken,
  requireAdmin,
  getUserAttendanceReport
);
router.get('/registration-requests', authenticateToken, requireAdmin, getRegistrationRequests);
router.put('/registration-requests/:id/approve', authenticateToken, requireAdmin, approveRequest);
router.put('/registration-requests/:id/reject', authenticateToken, requireAdmin, rejectRequest);

module.exports = router;