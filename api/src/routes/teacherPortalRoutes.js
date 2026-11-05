const express = require('express');
const authenticateToken = require('../middleware/authMiddleware');
const {
  getStudentFilters,
  getStudentsDtr
} = require('../controllers/teacherPortalController');

const router = express.Router();

router.use(authenticateToken);
router.get('/filters', getStudentFilters);
router.get('/students-dtr', getStudentsDtr);

module.exports = router;
