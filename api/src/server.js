const express = require('express');
const cors = require('cors');
if (process.env.NODE_ENV !== 'production' && !process.env.VERCEL) {
  require('dotenv').config();
}

const authRoutes = require('./routes/authRoutes');
const attendanceRoutes = require('./routes/attendanceRoutes');
const parentRoutes = require('./routes/parentRoutes');
const adminRoutes = require('./routes/adminRoutes');
const registrationRoutes = require('./routes/registrationRoutes');
const notificationRoutes = require('./routes/notificationRoutes');
const classScheduleRoutes = require('./routes/classScheduleRoutes');
const teacherPortalRoutes = require('./routes/teacherPortalRoutes');
const childLinkRoutes = require('./routes/childLinkRoutes');
const profileRoutes = require('./routes/profileRoutes');
const bulkAccountRoutes = require('./routes/bulkAccountRoutes');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
// 1mb so a resized profile photo (sent as base64) fits in the request body.
app.use(express.json({ limit: '1mb' }));

app.get('/', (req, res) => {
  res.json({
    message: 'Geolocation Attendance API is running!'
  });
});

app.use('/api/auth', authRoutes);
app.use('/api/attendance', attendanceRoutes);
app.use('/api/parent', parentRoutes);
app.use('/api/admin/bulk-accounts', bulkAccountRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/admin/class-schedules', classScheduleRoutes);
app.use('/api/teacher', teacherPortalRoutes);
app.use('/api/child-links', childLinkRoutes);
app.use('/api/profile', profileRoutes);
app.use('/api', registrationRoutes);

module.exports = app;

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`🚀 API server running on http://localhost:${PORT}`);
  });
}