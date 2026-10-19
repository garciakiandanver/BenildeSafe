const express = require('express');
const {
  getProfile,
  updateProfile,
  uploadPhoto,
  deletePhoto
} = require('../controllers/profileController');
const authenticateToken = require('../middleware/authMiddleware');

const router = express.Router();

router.get('/', authenticateToken, getProfile);
router.put('/', authenticateToken, updateProfile);
router.put('/photo', authenticateToken, uploadPhoto);
router.delete('/photo', authenticateToken, deletePhoto);

module.exports = router;