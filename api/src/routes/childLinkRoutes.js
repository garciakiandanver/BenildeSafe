const express = require('express');
const authenticateToken = require('../middleware/authMiddleware');
const {
  createChildLinkRequest,
  listMyChildLinkRequests,
  listChildLinkRequests,
  approveChildLink,
  rejectChildLink
} = require('../controllers/childLinkController');

const router = express.Router();

router.use(authenticateToken);

// Parent
router.post('/', createChildLinkRequest);
router.get('/mine', listMyChildLinkRequests);

// Administrator
router.get('/', listChildLinkRequests);
router.put('/:id/approve', approveChildLink);
router.put('/:id/reject', rejectChildLink);

module.exports = router;