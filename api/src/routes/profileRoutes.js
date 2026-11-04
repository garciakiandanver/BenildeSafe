const express = require('express');
const {
  getProfile,
  uploadPhoto,
  deletePhoto
} = require('../controllers/profileController');
const authenticateToken = require('../middleware/authMiddleware');

const router = express.Router();

router.get('/', authenticateToken, getProfile);
router.put('/photo', authenticateToken, uploadPhoto);
router.delete('/photo', authenticateToken, deletePhoto);

module.exports = router;
