const jwt = require('jsonwebtoken');
const pool = require('../config/database');
const { gps } = require('./attendanceController');

// Optional photo verification, once a day.
//
// 1. The app asks for a start token (valid for two minutes) and opens the
//    camera. The Android app opens the camera only, never the gallery.
// 2. The app sends the photo with the GPS position and the start token.
// 3. The server accepts it only while the token is valid and only when the
//    position is inside a campus, using the same rules as a time in.
//
// The server does not look at what is in the picture: there is no face
// detection or face recognition. "Verified" means a fresh photo was taken with
// the phone at the campus on that day.

const START_TOKEN_MINUTES = 2;
const MAX_PHOTO_BYTES = 600 * 1024;
const KEEP_IMAGES_DAYS = 30;
const PHOTO_PURPOSE = 'daily-photo';

const MANILA_TODAY = "(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date";
const manilaText = (column) =>
  `to_char(${column}, 'YYYY-MM-DD"T"HH24:MI:SS')`;

const isJpegOrPng = (buffer) =>
  (buffer.length > 3 &&
    buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) ||
  (buffer.length > 8 &&
    buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47);

const decodePhoto = (value) => {
  const text = String(value ?? '').replace(/^data:image\/[a-z]+;base64,/i, '');
  if (!text || !/^[A-Za-z0-9+/=\s]+$/.test(text)) return null;
  const buffer = Buffer.from(text, 'base64');
  if (buffer.length === 0 || buffer.length > MAX_PHOTO_BYTES) return null;
  return isJpegOrPng(buffer) ? buffer : null;
};

const todayPhoto = (userId) => pool.query(
  `SELECT ${manilaText('p.captured_at')} AS captured_at, c.campus_name
   FROM daily_photos p
   LEFT JOIN campuses c ON c.id = p.campus_id
   WHERE p.user_id = $1 AND p.photo_date = ${MANILA_TODAY}`,
  [userId]
);

// GET /api/attendance/photo/today
const getTodayPhotoStatus = async (req, res) => {
  try {
    if (gps.notAnAttendanceRole(req)) {
      return res.status(403).json({ message: gps.ATTENDANCE_ROLE_MESSAGE });
    }
    const row = await todayPhoto(req.user.userId);
    return res.json({
      verified: row.rowCount > 0,
      captured_at: row.rows[0]?.captured_at ?? null,
      campus_name: row.rows[0]?.campus_name ?? null
    });
  } catch (error) {
    console.error('Photo status error:', error);
    return res.status(500).json({ message: 'Could not load the photo status.' });
  }
};

// POST /api/attendance/photo/start
const startPhoto = async (req, res) => {
  try {
    if (gps.notAnAttendanceRole(req)) {
      return res.status(403).json({ message: gps.ATTENDANCE_ROLE_MESSAGE });
    }
    const row = await todayPhoto(req.user.userId);
    if (row.rowCount > 0) {
      return res.status(409).json({
        code: 'ALREADY_VERIFIED',
        message: 'You already verified today with a photo.'
      });
    }
    const startToken = jwt.sign(
      { userId: req.user.userId, purpose: PHOTO_PURPOSE },
      process.env.JWT_SECRET,
      { expiresIn: `${START_TOKEN_MINUTES}m` }
    );
    return res.json({ start_token: startToken, expires_in_seconds: START_TOKEN_MINUTES * 60 });
  } catch (error) {
    console.error('Photo start error:', error);
    return res.status(500).json({ message: 'Could not start the photo verification.' });
  }
};

// POST /api/attendance/photo
const submitPhoto = async (req, res) => {
  try {
    const userId = req.user.userId;
    if (gps.notAnAttendanceRole(req)) {
      return res.status(403).json({ message: gps.ATTENDANCE_ROLE_MESSAGE });
    }

    let started;
    try {
      started = jwt.verify(String(req.body.start_token ?? ''), process.env.JWT_SECRET);
    } catch (error) {
      return res.status(400).json({
        code: 'PHOTO_EXPIRED',
        message: 'The photo took too long or was not started from the app. Please take a new photo.'
      });
    }
    if (started.purpose !== PHOTO_PURPOSE || started.userId !== userId) {
      return res.status(400).json({
        code: 'PHOTO_EXPIRED',
        message: 'Please take a new photo from the app.'
      });
    }

    const photo = decodePhoto(req.body.photo);
    if (!photo) {
      return res.status(400).json({
        message: 'The photo could not be read or is too large. Please take it again.'
      });
    }

    const coordinates = gps.parseCoordinates(req.body.latitude, req.body.longitude);
    if (!coordinates) {
      return res.status(400).json({ message: 'Valid latitude and longitude are required.' });
    }
    const quality = gps.readGpsQuality(req.body);
    if (gps.REJECT_MOCK_LOCATION && quality.isMocked) {
      const rejected = gps.mockLocationResponse();
      return res.status(rejected.status).json(rejected.body);
    }
    if (gps.isWeakSignal(quality)) {
      return res.status(422).json({ code: 'LOW_ACCURACY', message: gps.weakSignalMessage() });
    }
    const { campus } = await gps.locateCampus(
      coordinates.latitude,
      coordinates.longitude,
      quality
    );
    if (!campus) {
      return res.status(403).json({
        code: 'OUTSIDE_CAMPUS',
        message: 'The photo was not accepted because your phone is outside the campus.'
      });
    }

    const saved = await pool.query(
      `INSERT INTO daily_photos (
         user_id, photo_date, captured_at, campus_id,
         latitude, longitude, accuracy, photo_jpeg
       )
       VALUES (
         $1, ${MANILA_TODAY}, CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila', $2,
         $3, $4, $5, $6
       )
       ON CONFLICT (user_id, photo_date) DO NOTHING
       RETURNING ${manilaText('captured_at')} AS captured_at`,
      [
        userId,
        campus.id,
        coordinates.latitude,
        coordinates.longitude,
        quality.accuracy,
        photo
      ]
    );
    if (saved.rowCount === 0) {
      return res.status(409).json({
        code: 'ALREADY_VERIFIED',
        message: 'You already verified today with a photo.'
      });
    }

    // Keep the database small and keep pictures only as long as needed.
    await pool.query(
      `UPDATE daily_photos SET photo_jpeg = NULL
       WHERE photo_jpeg IS NOT NULL
         AND photo_date < ${MANILA_TODAY} - ${KEEP_IMAGES_DAYS}`
    );

    return res.json({
      message: `Verified with a photo at ${campus.campus_name}.`,
      verified: true,
      captured_at: saved.rows[0].captured_at,
      campus_name: campus.campus_name
    });
  } catch (error) {
    console.error('Photo submit error:', error);
    return res.status(500).json({ message: 'Could not save the photo.' });
  }
};

const validDate = (value) =>
  /^\d{4}-\d{2}-\d{2}$/.test(String(value ?? '')) ? String(value) : null;

// GET /api/admin/photos?date=YYYY-MM-DD   (admin) the students verified that day
const getPhotosForDate = async (req, res) => {
  const date = validDate(req.query.date);
  if (!date) return res.status(400).json({ message: 'A date (YYYY-MM-DD) is required.' });
  try {
    const result = await pool.query(
      `SELECT p.user_id, ${manilaText('p.captured_at')} AS captured_at,
              c.campus_name, (p.photo_jpeg IS NOT NULL) AS has_image
       FROM daily_photos p
       LEFT JOIN campuses c ON c.id = p.campus_id
       WHERE p.photo_date = $1::date`,
      [date]
    );
    return res.json({ date, photos: result.rows });
  } catch (error) {
    console.error('Admin photo list error:', error);
    return res.status(500).json({ message: 'Could not load the verification photos.' });
  }
};

// GET /api/admin/photos/:userId/:date   (admin) one photo
const getPhoto = async (req, res) => {
  const date = validDate(req.params.date);
  if (!date) return res.status(400).json({ message: 'A date (YYYY-MM-DD) is required.' });
  try {
    const result = await pool.query(
      `SELECT ${manilaText('p.captured_at')} AS captured_at, c.campus_name,
              p.latitude, p.longitude, p.accuracy, p.photo_jpeg
       FROM daily_photos p
       LEFT JOIN campuses c ON c.id = p.campus_id
       WHERE p.user_id = $1::uuid AND p.photo_date = $2::date`,
      [String(req.params.userId ?? ''), date]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'No verification photo for that day.' });
    }
    const row = result.rows[0];
    return res.json({
      captured_at: row.captured_at,
      campus_name: row.campus_name,
      latitude: row.latitude,
      longitude: row.longitude,
      accuracy: row.accuracy,
      photo: row.photo_jpeg
        ? `data:image/jpeg;base64,${row.photo_jpeg.toString('base64')}`
        : null
    });
  } catch (error) {
    console.error('Admin photo error:', error);
    return res.status(500).json({ message: 'Could not load the photo.' });
  }
};

module.exports = {
  getTodayPhotoStatus,
  startPhoto,
  submitPhoto,
  getPhotosForDate,
  getPhoto,
  _test: { decodePhoto }
};
