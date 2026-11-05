const pool = require('../config/database');
const {
  parseCampusBoundary,
  isInside,
  locate,
  distanceToEdgeMeters
} = require('../services/campusBoundary');
const { createAttendanceNotifications } = require('../services/notificationService');

// ---------------------------------------------------------------------------
// Time zone
//
// Time in and time out are stored as Manila wall-clock time
// (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'). If the raw column were sent
// as JSON, node-pg would turn it into a Date using the time zone of the server
// (UTC on Vercel), and the phone would then add another 8 hours. So these
// columns are always sent as plain text with no time zone, for example
// "2026-10-18T22:59:00", which the app reads as Manila time.
// ---------------------------------------------------------------------------
const manilaText = (column) =>
  `to_char(${column}, 'YYYY-MM-DD"T"HH24:MI:SS')`;

// Added to a RETURNING clause next to *.
const ATTENDANCE_TEXT_COLUMNS = `${manilaText('time_in')} AS time_in_text, ${manilaText('time_out')} AS time_out_text`;

// An attendance row with time_in / time_out as Manila text.
const publicAttendance = ({ time_in_text, time_out_text, ...row }) => ({
  ...row,
  time_in: time_in_text,
  time_out: time_out_text
});

const parseCoordinates = (latitude, longitude) => {
  if (
    latitude === undefined ||
    latitude === null ||
    latitude === '' ||
    longitude === undefined ||
    longitude === null ||
    longitude === ''
  ) {
    return null;
  }

  const parsedLatitude = Number(latitude);
  const parsedLongitude = Number(longitude);
  if (
    !Number.isFinite(parsedLatitude) ||
    !Number.isFinite(parsedLongitude) ||
    parsedLatitude < -90 ||
    parsedLatitude > 90 ||
    parsedLongitude < -180 ||
    parsedLongitude > 180
  ) {
    return null;
  }

  // 0, 0 is what a phone reports when it has no GPS fix at all.
  if (parsedLatitude === 0 && parsedLongitude === 0) {
    return null;
  }

  return { latitude: parsedLatitude, longitude: parsedLongitude };
};

// ---------------------------------------------------------------------------
// GPS accuracy
//
// Every GPS reading has an error radius ("accuracy", in meters). Near the edge
// of the campus a reading can land on the wrong side of the line by that much,
// so a student standing still could be reported as leaving and a parent warned
// for nothing. The app sends the accuracy of each reading and the server:
//   - refuses a time in when the signal is too weak to trust,
//   - ignores weak readings while the student is already timed in,
//   - does not start the "outside" timer for a reading that is outside by less
//     than its own accuracy (it cannot tell which side of the line they are on).
// Older versions of the app send no accuracy and keep the previous behaviour.
// ---------------------------------------------------------------------------
const MAX_GPS_ACCURACY_METERS =
  Number(process.env.MAX_GPS_ACCURACY_METERS) > 0
    ? Number(process.env.MAX_GPS_ACCURACY_METERS)
    : 100;

// How far outside the drawn boundary still counts as being at the campus.
//
// A phone indoors cannot see the sky well, so its reading drifts towards the
// street, often by 10 to 40 metres. Without an allowance a student sitting in a
// classroom is refused, and the only way out is to draw a campus far larger
// than it really is. The drawn boundary stays the true outline of the campus
// and this allowance absorbs the error of the reading instead.
//
// The allowance is the tolerance plus the error the phone reports, and the
// error can never add more than the tolerance itself, so it stays between
// BOUNDARY_TOLERANCE_METERS and twice that.
const BOUNDARY_TOLERANCE_METERS =
  Number(process.env.BOUNDARY_TOLERANCE_METERS) >= 0
    ? Number(process.env.BOUNDARY_TOLERANCE_METERS)
    : 25;

const allowanceMeters = ({ accuracy }) =>
  BOUNDARY_TOLERANCE_METERS +
  Math.min(accuracy ?? 0, BOUNDARY_TOLERANCE_METERS);

// Is this reading at the campus: inside the line, or outside it by no more
// than the allowance?
const countsAsInside = (position, quality) =>
  position.inside || position.distanceToEdge <= allowanceMeters(quality);

// Set REJECT_MOCK_LOCATION=true to refuse readings flagged as fake GPS.
const REJECT_MOCK_LOCATION = process.env.REJECT_MOCK_LOCATION === 'true';

const readGpsQuality = (body) => {
  const raw = body?.accuracy;
  const accuracy =
    raw === undefined || raw === null || raw === '' ? NaN : Number(raw);
  return {
    accuracy: Number.isFinite(accuracy) && accuracy >= 0 ? accuracy : null,
    isMocked: body?.is_mocked === true || body?.is_mocked === 'true'
  };
};

const mockLocationResponse = () => ({
  status: 403,
  body: {
    code: 'MOCK_LOCATION',
    message: 'A fake (mock) GPS location was detected. Turn off mock locations and try again.'
  }
});

const isWeakSignal = ({ accuracy }) =>
  accuracy !== null && accuracy > MAX_GPS_ACCURACY_METERS;

// No margin of error in the wording: a student reading "about 98 m off" has
// nothing to do with that number, and it reads like a fault in the app. The
// figure is still sent as accuracy_m and written to the log.
const weakSignalMessage = () =>
  'Your phone cannot pin down your location well enough right now. Move to an open area, wait a few seconds, then try again.';

// Which campus is the point in? When it is in none, also say which campus is
// the closest and how far away (meters), so a refusal can be explained.
const locateCampus = async (latitude, longitude, quality = { accuracy: null }) => {
  const result = await pool.query(`
    SELECT id, campus_code, campus_name, boundary_coordinates
    FROM campuses
    WHERE boundary_coordinates IS NOT NULL
    ORDER BY campus_name
  `);
  let nearest = null;
  for (const campus of result.rows) {
    const { feature, problems } = parseCampusBoundary(campus.boundary_coordinates);
    if (!feature) {
      // One broken polygon must not stop everyone from timing in at other campuses.
      console.error(
        `Campus ${campus.campus_code} has an unusable boundary: ${problems.join(' ')}`
      );
      continue;
    }
    if (isInside(feature, longitude, latitude)) {
      return { campus, nearest: null, strictInside: true };
    }
    const distance = distanceToEdgeMeters(feature, longitude, latitude);
    if (!nearest || distance < nearest.distance) nearest = { campus, distance };
  }
  // Just outside the line, by no more than the allowance: still at that campus.
  if (nearest && nearest.distance <= allowanceMeters(quality)) {
    return { campus: nearest.campus, nearest: null, strictInside: false };
  }
  return { campus: null, nearest, strictInside: false };
};

// Metres below a kilometre, kilometres above it. "4690 m away" is a number to
// decode; "4.7 km away" is a distance a person can picture.
const describeDistance = (meters) =>
  meters >= 1000
    ? `${(meters / 1000).toFixed(1)} km`
    : `${Math.round(meters)} m`;

// The sentence added to a refusal. It says how far outside the student is, and
// warns when the phone is too unsure of itself for that distance to be trusted
// — which is what tells a campus drawn too small apart from a poor reading.
//
// The margin of error itself is deliberately left out of the wording: it is
// still sent as accuracy_m and written to the log, where it is useful, but a
// student cannot act on "±98 m" and it only makes the app look broken.
const describeOutside = (nearest, { accuracy }) => {
  const parts = [];
  if (nearest) {
    parts.push(
      `The nearest campus (${nearest.campus.campus_name}) is about ${describeDistance(nearest.distance)} away.`
    );
  }
  if (accuracy !== null && nearest && accuracy >= nearest.distance) {
    parts.push(
      'Your phone is not sure enough of its location to tell, so you may really be inside. Try again outdoors or near a window.'
    );
  }
  return parts.join(' ');
};

// Safe to send to the app and to read in the server log.
const outsideFields = (nearest, { accuracy }) => ({
  accuracy_m: accuracy === null ? null : Math.round(accuracy),
  nearest_campus: nearest
    ? {
        name: nearest.campus.campus_name,
        code: nearest.campus.campus_code,
        distance_m: Math.round(nearest.distance)
      }
    : null
});

// Only students record their own attendance. Teachers use the system to follow
// the classes they teach, and admins and parents never time in at all.
const ATTENDANCE_ROLE = 'student';
const notAnAttendanceRole = (req) =>
  (req.user.role ?? '').toLowerCase() !== ATTENDANCE_ROLE;
const ATTENDANCE_ROLE_MESSAGE =
  'Only students record attendance in BenildeSafe.';

const detectCampus = async (req, res) => {
  try {
    if (notAnAttendanceRole(req)) {
      return res.status(403).json({ message: ATTENDANCE_ROLE_MESSAGE });
    }

    const coordinates = parseCoordinates(
      req.body.latitude,
      req.body.longitude
    );
    if (!coordinates) {
      return res.status(400).json({
        message: 'Valid latitude and longitude are required.'
      });
    }

    const quality = readGpsQuality(req.body);
    if (REJECT_MOCK_LOCATION && quality.isMocked) {
      const rejected = mockLocationResponse();
      return res.status(rejected.status).json(rejected.body);
    }
    if (isWeakSignal(quality)) {
      return res.status(422).json({
        code: 'LOW_ACCURACY',
        message: weakSignalMessage()
      });
    }

    const { campus, nearest } = await locateCampus(
      coordinates.latitude,
      coordinates.longitude,
      quality
    );
    if (!campus) {
      return res.status(404).json({
        message: [
          'Your current location is outside all configured campus boundaries.',
          describeOutside(nearest, quality)
        ]
          .filter(Boolean)
          .join(' '),
        ...outsideFields(nearest, quality)
      });
    }

    const activeResult = await pool.query(
      `
      SELECT c.id, c.campus_code, c.campus_name
      FROM attendance a
      JOIN campuses c ON c.id = a.campus_id
      WHERE a.user_id = $1
        AND a.time_in::date =
          (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
        AND a.time_in IS NOT NULL
        AND a.time_out IS NULL
      ORDER BY a.time_in DESC
      LIMIT 1
      `,
      [req.user.userId]
    );
    const activeCampus = activeResult.rows[0] ?? null;
    const canCheckOutHere = activeCampus
      ? String(activeCampus.id) === String(campus.id)
      : null;
    const message = activeCampus
      ? canCheckOutHere
        ? `You are at ${campus.campus_name}, where your active session was started. You can time out here.`
        : `You are at ${campus.campus_name}, but your active session was started at ${activeCampus.campus_name}. Time out at ${activeCampus.campus_name}.`
      : `You are at ${campus.campus_name}. You can time in here.`;

    return res.json({
      campus: {
        id: campus.id,
        code: campus.campus_code,
        name: campus.campus_name
      },
      activeAttendanceCampus: activeCampus
        ? {
          id: activeCampus.id,
          code: activeCampus.campus_code,
          name: activeCampus.campus_name
        }
        : null,
      canCheckOutHere,
      message
    });
  } catch (error) {
    console.error('Campus detection error:', error);
    return res.status(500).json({
      message: 'Could not detect the campus at your current location.'
    });
  }
};

const checkIn = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { latitude, longitude } = req.body;
    const coordinates = parseCoordinates(latitude, longitude);
    if (!coordinates) {
      return res.status(400).json({
        message: 'Valid latitude and longitude are required.'
      });
    }
    const { latitude: latitudeValue, longitude: longitudeValue } = coordinates;

    if (notAnAttendanceRole(req)) {
      return res.status(403).json({ message: ATTENDANCE_ROLE_MESSAGE });
    }

    const quality = readGpsQuality(req.body);
    if (REJECT_MOCK_LOCATION && quality.isMocked) {
      const rejected = mockLocationResponse();
      return res.status(rejected.status).json(rejected.body);
    }
    if (isWeakSignal(quality)) {
      return res.status(422).json({
        code: 'LOW_ACCURACY',
        message: weakSignalMessage()
      });
    }

    // Automatic time in (sent by the app by itself, not by a button). It must
    // answer quietly: a student who is not at the campus is the normal case, not
    // an error. It also needs a reading that is really inside the drawn line, not
    // only inside the allowance, so a student standing just outside the gate is
    // not timed in and then timed straight out again.
    const isAuto = req.body.auto === true || req.body.auto === 'true';
    const skipAuto = (reason, message) =>
      res.json({ auto_skipped: true, reason, message });

    if (isAuto && isWeakSignal(quality)) {
      return skipAuto('weak', weakSignalMessage());
    }

    const { campus: matchedCampus, nearest, strictInside } = await locateCampus(
      latitudeValue,
      longitudeValue,
      quality
    );
    if (!matchedCampus) {
      if (isAuto) {
        return skipAuto('outside', 'You are outside the campus.');
      }
      console.log('Time in refused, outside every campus:', JSON.stringify({
        userId,
        latitude: latitudeValue,
        longitude: longitudeValue,
        ...outsideFields(nearest, quality)
      }));
      return res.status(403).json({
        message: [
          'You are outside the campus boundary.',
          describeOutside(nearest, quality)
        ]
          .filter(Boolean)
          .join(' '),
        ...outsideFields(nearest, quality)
      });
    }
    if (isAuto && !strictInside) {
      return skipAuto(
        'edge',
        'You are right at the campus boundary. Move a little further inside.'
      );
    }

    const openSession = await pool.query(
      `
      SELECT id
      FROM attendance
      WHERE user_id = $1
        AND time_out IS NULL
        AND time_in::date =
          (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
      LIMIT 1
      `,
      [userId]
    );

    if (openSession.rows.length > 0) {
      if (isAuto) {
        return skipAuto('open', 'You are already timed in.');
      }
      return res.status(409).json({
        message: 'Check out of your current attendance session before checking in again.'
      });
    }

    // There is no schedule and no late: every time in is simply present. The
    // day's record is the list of times in and out (the daily time record).
    const status = 'present';
    let notificationWarning;
    const attendanceResult = await pool.query(
      `
      INSERT INTO attendance (
        user_id,
        campus_id,
        attendance_date,
        time_in,
        latitude_in,
        longitude_in,
        status
      )
      VALUES (
        $1,
        $2,
        (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date,
        CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila',
        $3,
        $4,
        $5
      )
      RETURNING *, ${ATTENDANCE_TEXT_COLUMNS}
      `,
      [
        userId,
        matchedCampus.id,
        latitudeValue,
        longitudeValue,
        status
      ]
    );

    try {
      await createAttendanceNotifications({
        userId,
        title: 'Attendance check-in recorded',
        message: isAuto
          ? `You were timed in automatically at ${matchedCampus.campus_name}.`
          : `Your attendance was recorded at ${matchedCampus.campus_name}.`,
        type: 'attendance_check_in'
      });
    } catch (error) {
      console.error('Check-in notification error:', error);
      notificationWarning = 'Attendance was recorded, but notifications could not be created.';
    }

    return res.status(201).json({
      auto: isAuto,
      message: isAuto ? 'Timed in automatically.' : 'Check-in successful.',
      ...(notificationWarning ? { notificationWarning } : {}),
      campus: {
        id: matchedCampus.id,
        code: matchedCampus.campus_code,
        name: matchedCampus.campus_name
      },
      attendance: publicAttendance(attendanceResult.rows[0])
    });
  } catch (error) {
    console.error('CHECK-IN ERROR:', error);
    return res.status(500).json({
      message: 'Server error while checking in.'
    });
  }
};

//chechOut or Time-out

const checkOut = async (req, res) => {
  try {
    if (notAnAttendanceRole(req)) {
      return res.status(403).json({ message: ATTENDANCE_ROLE_MESSAGE });
    }
    const userId = req.user.userId;
    const { latitude, longitude } = req.body;
    const coordinates = parseCoordinates(latitude, longitude);
    if (!coordinates) {
      return res.status(400).json({
        message: 'Valid latitude and longitude are required.'
      });
    }

    // Find today's active attendance and its campus boundary
    const result = await pool.query(
      `
      SELECT
        a.id,
        a.campus_id,
        a.time_in,
        c.campus_code,
        c.campus_name,
        c.boundary_coordinates
      FROM attendance a
      JOIN campuses c ON c.id = a.campus_id
      WHERE a.user_id = $1
        AND a.time_in::date =
          (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
        AND a.time_in IS NOT NULL
        AND a.time_out IS NULL
      ORDER BY a.time_in DESC
      LIMIT 1
      `,
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: 'No active attendance record found for today.'
      });
    }

    const attendance = result.rows[0];

    const quality = readGpsQuality(req.body);
    if (REJECT_MOCK_LOCATION && quality.isMocked) {
      const rejected = mockLocationResponse();
      return res.status(rejected.status).json(rejected.body);
    }

    // The polygon of the campus where the student checked in
    const { feature: polygon, problems } = parseCampusBoundary(
      attendance.boundary_coordinates
    );
    if (!polygon) {
      console.error(
        `Campus ${attendance.campus_code} has an unusable boundary: ${problems.join(' ')}`
      );
      return res.status(500).json({
        message: 'The campus boundary is not set up correctly. Please contact the administrator.'
      });
    }

    // Must still be at the SAME campus. A reading that only just misses the
    // line, by no more than the allowance, is given the benefit of the doubt.
    const position = locate(polygon, coordinates.longitude, coordinates.latitude);
    if (!countsAsInside(position, quality)) {
      return res.status(403).json({
        message: `You cannot check out here. You checked in at ${attendance.campus_name}. Please check out from the same campus. ${describeOutside(
          { campus: { campus_name: attendance.campus_name }, distance: position.distanceToEdge },
          quality
        )}`.trim(),
        accuracy_m: quality.accuracy === null ? null : Math.round(quality.accuracy),
        distance_m: Math.round(position.distanceToEdge)
      });
    }

    // Update checkout information
    const updated = await pool.query(
      `
      UPDATE attendance
      SET
        time_out = CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila',
        latitude_out = $1,
        longitude_out = $2,
        updated_at = CURRENT_TIMESTAMP
      WHERE id = $3
      RETURNING *, ${ATTENDANCE_TEXT_COLUMNS}
      `,
      [
        coordinates.latitude,
        coordinates.longitude,
        attendance.id
      ]
    );

    let notificationWarning;
    try {
      await createAttendanceNotifications({
        userId,
        title: 'Attendance check-out recorded',
        message: `Your attendance check-out was recorded at ${attendance.campus_name}.`,
        type: 'attendance_check_out'
      });
    } catch (error) {
      console.error('Check-out notification error:', error);
      notificationWarning = 'Attendance was recorded, but notifications could not be created.';
    }

    return res.json({
      message: 'Check-out successful.',
      ...(notificationWarning ? { notificationWarning } : {}),
      campus: {
        id: attendance.campus_id,
        code: attendance.campus_code,
        name: attendance.campus_name
      },
      attendance: publicAttendance(updated.rows[0])
    });

  } catch (error) {
    console.error('CHECK-OUT ERROR:', error);

    return res.status(500).json({
      message: 'Server error while checking out.',
      error: error.message
    });
  }
};

//Update Location
const updateLocation = async (req, res) => {
  try {
    if (notAnAttendanceRole(req)) {
      return res.status(403).json({ message: ATTENDANCE_ROLE_MESSAGE });
    }
    const userId = req.user.userId;
    const { latitude, longitude } = req.body;
    const coordinates = parseCoordinates(latitude, longitude);
    if (!coordinates) {
      return res.status(400).json({
        message: 'Valid latitude and longitude are required.'
      });
    }

    // Find active attendance and its campus
    const result = await pool.query(
      `
      SELECT
        a.id,
        a.campus_id,
        a.time_in,
        a.outside_since,
        c.campus_code,
        c.campus_name,
        c.boundary_coordinates
      FROM attendance a
      JOIN campuses c ON c.id = a.campus_id
      WHERE a.user_id = $1
        AND a.time_in::date =
          (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
        AND a.time_in IS NOT NULL
        AND a.time_out IS NULL
      ORDER BY a.time_in DESC
      LIMIT 1
      `,
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: 'No active attendance session.'
      });
    }

    const attendance = result.rows[0];

    const quality = readGpsQuality(req.body);
    if (REJECT_MOCK_LOCATION && quality.isMocked) {
      const rejected = mockLocationResponse();
      return res.status(rejected.status).json(rejected.body);
    }

    // Use the SAME campus where the student checked in
    const { feature: polygon, problems } = parseCampusBoundary(
      attendance.boundary_coordinates
    );
    if (!polygon) {
      console.error(
        `Campus ${attendance.campus_code} has an unusable boundary: ${problems.join(' ')}`
      );
      return res.status(500).json({
        message: 'The campus boundary is not set up correctly. Please contact the administrator.'
      });
    }

    const weakSignal = isWeakSignal(quality);
    const position = weakSignal
      ? null
      : locate(polygon, coordinates.longitude, coordinates.latitude);
    // The same allowance as time in: a reading just outside the line does not
    // mean the student left the campus.
    const nearEdge =
      Boolean(position) && position.distanceToEdge <= allowanceMeters(quality);
    // Outside the line, but by less than the error of the reading.
    const outsideNearEdge = nearEdge && !position.inside;
    // Inside the line, but by less than the error, while the outside timer is
    // running: not enough proof to cancel the timer.
    const insideNearEdgeWhileTimed =
      nearEdge && position.inside && attendance.outside_since !== null;
    const uncertain = weakSignal || outsideNearEdge || insideNearEdgeWhileTimed;

    // A reading that cannot tell which side of the line the student is on
    // changes nothing: it neither times the student out nor cancels anything.
    if (uncertain) {
      return res.json({
        attendance_id: attendance.id,
        campus: attendance.campus_name,
        inside_campus: true,
        status: 'Inside Campus',
        message: weakSignal
          ? `Waiting for a better GPS signal (about ${Math.round(quality.accuracy)} m off).`
          : 'You are right at the campus boundary. Move a little further inside for a clearer reading.',
        ignored: true,
        outside_since: null
      });
    }

    // STUDENT IS INSIDE THEIR CAMPUS: nothing to record. A session that an older
    // version left with an outside timer running is cleared quietly.
    if (position.inside) {
      if (attendance.outside_since !== null) {
        await pool.query(
          `
          UPDATE attendance
          SET outside_since = NULL, updated_at = CURRENT_TIMESTAMP
          WHERE id = $1
          `,
          [attendance.id]
        );
      }

      return res.json({
        attendance_id: attendance.id,
        campus: attendance.campus_name,
        inside_campus: true,
        status: 'Inside Campus',
        outside_since: null
      });
    }

    // -----------------------------------------
    // STUDENT IS OUTSIDE THEIR CAMPUS
    // -----------------------------------------

    // A single reading outside can be a GPS jump (common on a browser, or
    // indoors). A newer app sends `confirmed: false` with an ordinary reading
    // and is asked to send a second one a few seconds later with
    // `confirmed: true`; nothing is recorded and nobody is alerted until then.
    // An older app does not send the field and is handled as before.
    if (req.body.confirmed === false) {
      return res.json({
        attendance_id: attendance.id,
        campus: attendance.campus_name,
        inside_campus: true,
        status: 'Inside Campus',
        message: 'Checking your location again.',
        confirm_required: true,
        ignored: true,
        outside_since: null
      });
    }

    // -----------------------------------------
    // LEFT THE CAMPUS -> AUTOMATIC TIME-OUT, AT ONCE
    // -----------------------------------------
    // The student is timed out the moment a confirmed reading is outside the
    // campus, and the linked parent is told. The time out is the time of this
    // reading. When the student comes back inside, the app times them in again
    // as a new record, so one day can hold several times in and out.
    const updated = await pool.query(
      `
      UPDATE attendance
      SET
        time_out = CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila',
        latitude_out = $1,
        longitude_out = $2,
        outside_since = NULL,
        status = 'timeout',
        updated_at = CURRENT_TIMESTAMP
      WHERE id = $3
      RETURNING *, ${ATTENDANCE_TEXT_COLUMNS}
      `,
      [
        coordinates.latitude,
        coordinates.longitude,
        attendance.id
      ]
    );

    let notificationWarning;
    try {
      await createAttendanceNotifications({
        userId,
        title: 'You left the campus',
        message: `You left ${attendance.campus_name}, so a time out was recorded automatically.`,
        type: 'attendance_timeout'
      });
    } catch (error) {
      console.error('Automatic time-out notification error:', error);
      notificationWarning = 'Attendance was recorded, but notifications could not be created.';
    }

    return res.json({
      attendance_id: attendance.id,
      campus: attendance.campus_name,
      inside_campus: false,
      status: 'Timed Out',
      message: 'You left the campus, so you were timed out automatically.',
      ...(notificationWarning ? { notificationWarning } : {}),
      attendance: publicAttendance(updated.rows[0])
    });

  } catch (error) {
    console.error('LOCATION UPDATE ERROR:', error);

    return res.status(500).json({
      message: 'Server error while updating location.',
      error: error.message
    });
  }
};

const getActiveAttendance = async (req, res) => {
  try {
    if (notAnAttendanceRole(req)) {
      return res.json({ active: false });
    }
    const userId = req.user.userId;

    const result = await pool.query(
      `
      SELECT
        a.id,
        a.campus_id,
        a.attendance_date,
        a.time_in,
        ${manilaText('a.time_in')} AS time_in_text,
        a.time_out,
        a.outside_since,
        a.latitude_in,
        a.longitude_in,
        c.campus_code,
        c.campus_name
      FROM attendance a
      JOIN campuses c ON c.id = a.campus_id
      WHERE a.user_id = $1
        AND a.time_in::date =
          (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
        AND a.time_in IS NOT NULL
        AND a.time_out IS NULL
      ORDER BY a.time_in DESC
      LIMIT 1
      `,
      [userId]
    );

    if (result.rows.length === 0) {
      return res.json({
        active: false
      });
    }

    const attendance = result.rows[0];

    return res.json({
      active: true,
      attendance_id: attendance.id,
      campus: {
        id: attendance.campus_id,
        code: attendance.campus_code,
        name: attendance.campus_name
      },
      time_in: attendance.time_in_text,
      outside_since: attendance.outside_since,
      latitude_in: attendance.latitude_in,
      longitude_in: attendance.longitude_in
    });

  } catch (error) {
    console.error('GET ACTIVE ATTENDANCE ERROR:', error);

    return res.status(500).json({
      message: 'Server error while getting active attendance.'
    });
  }
};

// Get attendance history for the logged-in student or teacher.
// One record per time in; a day can hold several. The status is present, timeout or absent.
const getAttendanceHistory = async (req, res) => {
  try {
    const userId = req.user.userId;

    const result = await pool.query(
      `
      SELECT
        a.id,
        a.attendance_date::text AS date_key,
        ${manilaText('a.time_in')} AS time_in_text,
        ${manilaText('a.time_out')} AS time_out_text,
        a.status,
        c.campus_name
      FROM attendance a
      JOIN campuses c ON c.id = a.campus_id
      WHERE a.user_id = $1
      ORDER BY a.attendance_date DESC, a.time_in DESC
      `,
      [userId]
    );

    const attendance = result.rows.map((row) => ({
      id: row.id,
      // "2026-10-18": the date as text, so the server time zone cannot move it
      attendance_date: row.date_key,
      time_in: row.time_in_text,
      time_out: row.time_out_text,
      status: row.status,
      campus_name: row.campus_name
    }));

    return res.json({ attendance });

  } catch (error) {
    console.error('GET ATTENDANCE HISTORY ERROR:', error);

    return res.status(500).json({
      message: 'Server error while getting attendance history.'
    });
  }
};

module.exports = {
  detectCampus,
  checkIn,
  checkOut,
  updateLocation,
  getActiveAttendance,
  getAttendanceHistory,
  // Shared with the photo verification controller.
  gps: {
    parseCoordinates,
    readGpsQuality,
    isWeakSignal,
    weakSignalMessage,
    mockLocationResponse,
    locateCampus,
    notAnAttendanceRole,
    ATTENDANCE_ROLE_MESSAGE,
    REJECT_MOCK_LOCATION
  }
};