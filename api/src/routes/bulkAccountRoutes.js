const express = require('express');
const multer = require('multer');
const authenticateToken = require('../middleware/authMiddleware');
const {
  previewBulkAccounts,
  commitBulkAccounts,
  getPendingAccounts,
  resendCredentials
} = require('../controllers/bulkAccountController');

const router = express.Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024, files: 1 }
});

const requireAdmin = (req, res, next) => {
  if (req.user.role?.toLowerCase() !== 'admin') {
    return res.status(403).json({
      message: 'Administrator access is required.'
    });
  }
  return next();
};

const handleAccountsFile = (req, res, next) => {
  upload.single('file')(req, res, (error) => {
    if (error) {
      return res.status(400).json({
        message: error.code === 'LIMIT_FILE_SIZE'
          ? 'The file must be 2 MB or smaller.'
          : 'Could not process the uploaded file.'
      });
    }
    return next();
  });
};

router.use(authenticateToken, requireAdmin);
router.post('/preview', handleAccountsFile, previewBulkAccounts);
router.post('/commit', commitBulkAccounts);
router.get('/pending', getPendingAccounts);
router.post('/resend', resendCredentials);

module.exports = router;
