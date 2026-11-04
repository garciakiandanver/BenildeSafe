const pool = require('../config/database');
const {
  parseCampusBoundary,
  isInside,
  locate,
  distanceToEdgeMeters
} = require('../services/campusBoundary');
const { createAttendanceNotifications } = require('../services/notificationService');

// A student who stays outside the campus is warned (together with the parent)
// once they have been outside this many minutes. The automatic time-out is at 30.
const TIMEOUT_WARNING_AFTER_MINUTES = 25;

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
    if (isInside(feature, longitude, latitude)) return { campus, nearest: null };
    const distance = distanceToEdgeMeters(feature, longitude, latitude);
    if (!nearest || distance < nearest.distance) nearest = { campus, distance };
  }
  // Just outside the line, by no more than the allowance: still at that campus.
  if (nearest && nearest.distance <= allowanceMeters(quality)) {
    return { campus: nearest.campus, nearest: null };
  }
  return { campus: null, nearest };
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

    const role = req.user.role?.toLowerCase();
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

    const { campus: matchedCampus, nearest } = await locateCampus(
      latitudeValue,
      longitudeValue,
      quality
    );
    if (!matchedCampus) {
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
      return res.status(409).json({
        message: 'Check out of your current attendance session before checking in again.'
      });
    }

    // Attendance is per day. The first time in of a student's school day is
    // late when it is after the late time of the first class; every other time
    // in (and every teacher time in) is simply present.
    const lateCheck = await lateStatusFor(userId, role);
    const status = lateCheck.late ? 'late' : 'present';
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
        message: lateCheck.late
          ? `Your attendance was recorded at ${matchedCampus.campus_name}. You arrived after ${clockLabel(lateCheck.lateAfter)}, so today is marked late.`
          : `Your attendance was recorded at ${matchedCampus.campus_name}.`,
        type: 'attendance_check_in'
      });
    } catch (error) {
      console.error('Check-in notification error:', error);
      notificationWarning = 'Attendance was recorded, but notifications could not be created.';
    }

    return res.status(201).json({
      message: 'Check-in successful.',
      ...(notificationWarning ? { notificationWarning } : {}),
      campus: {
        id: matchedCampus.id,
        code: matchedCampus.campus_code,
        name: matchedCampus.campus_name
      },
      schedule: null,
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
      schedule: null,
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
    // changes nothing: it neither starts nor cancels the outside timer. The one
    // exception: once the 30 minutes have run out, a reading just outside the
    // line still counts towards the automatic time-out.
    const timerExpired =
      attendance.outside_since !== null &&
      (Date.now() - new Date(attendance.outside_since).getTime()) / (1000 * 60) >= 30;

    if (uncertain && !(outsideNearEdge && timerExpired)) {
      const stillOutside = attendance.outside_since !== null;
      return res.json({
        attendance_id: attendance.id,
        campus: attendance.campus_name,
        inside_campus: !stillOutside,
        status: stillOutside ? 'Outside Campus' : 'Inside Campus',
        message: weakSignal
          ? `Waiting for a better GPS signal (about ${Math.round(quality.accuracy)} m off).`
          : 'You are right at the campus boundary. Move a little further inside for a clearer reading.',
        ignored: true,
        outside_since: attendance.outside_since
      });
    }

    const isInside = !uncertain && position.inside;

    // STUDENT IS INSIDE THEIR CAMPUS
    if (isInside) {

      // If they previously went outside,
      // clear the outside timer.
      let notificationWarning;
      if (attendance.outside_since !== null) {
        await pool.query(
          `
          UPDATE attendance
          SET
            outside_since = NULL,
            updated_at = CURRENT_TIMESTAMP
          WHERE id = $1
          `,
          [attendance.id]
        );

        // Tell the student, and the parent, that they are back on campus.
        try {
          await createAttendanceNotifications({
            userId,
            title: 'You are back on campus',
            message: `You are back inside ${attendance.campus_name}. The automatic time-out timer has been cancelled.`,
            type: 'attendance_returned'
          });
        } catch (error) {
          console.error('Return-to-campus notification error:', error);
          notificationWarning = 'Notifications could not be created.';
        }
      }

      return res.json({
        attendance_id: attendance.id,
        campus: attendance.campus_name,
        inside_campus: true,
        status: 'Inside Campus',
        ...(notificationWarning ? { notificationWarning } : {}),
        outside_since: null
      });
    }

    // -----------------------------------------
    // STUDENT IS OUTSIDE THEIR CAMPUS
    // -----------------------------------------

    // First time detected outside
    if (attendance.outside_since === null) {

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

      const updated = await pool.query(
        `
        UPDATE attendance
        SET
          outside_since = CURRENT_TIMESTAMP,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = $1
        RETURNING outside_since
        `,
        [attendance.id]
      );

      // Tell the student, and the parent, that the boundary was crossed.
      let notificationWarning;
      try {
        await createAttendanceNotifications({
          userId,
          title: 'You left the campus boundary',
          message: `You are outside ${attendance.campus_name}. You will be timed out automatically in 30 minutes unless you return.`,
          type: 'attendance_left_boundary'
        });
      } catch (error) {
        console.error('Left-boundary notification error:', error);
        notificationWarning = 'Notifications could not be created.';
      }

      return res.json({
        attendance_id: attendance.id,
        campus: attendance.campus_name,
        inside_campus: false,
        status: 'Outside Campus',
        message: 'You are outside your campus. The 30-minute timer has started.',
        ...(notificationWarning ? { notificationWarning } : {}),
        outside_since: updated.rows[0].outside_since
      });
    }

    // -----------------------------------------
    // CHECK IF 30 MINUTES HAVE PASSED
    // -----------------------------------------

    const outsideSince = new Date(attendance.outside_since);
    const now = new Date();

    const minutesOutside =
      (now - outsideSince) / (1000 * 60);

    // Still within 30-minute break
    if (minutesOutside < 30) {

      const remainingMinutes =
        Math.ceil(30 - minutesOutside);

      // Shortly before the time-out, warn the student and the parent.
      let notificationWarning;
      if (minutesOutside >= TIMEOUT_WARNING_AFTER_MINUTES) {
        try {
          await createAttendanceNotifications({
            userId,
            title: 'Automatic time-out soon',
            message: `You have been outside ${attendance.campus_name} for ${Math.floor(minutesOutside)} minutes. You will be timed out automatically in about ${remainingMinutes} minute(s) unless you return.`,
            type: 'attendance_timeout_warning'
          });
        } catch (error) {
          console.error('Time-out warning notification error:', error);
          notificationWarning = 'Notifications could not be created.';
        }
      }

      return res.json({
        attendance_id: attendance.id,
        campus: attendance.campus_name,
        inside_campus: false,
        status: 'Outside Campus',
        message: `You are outside campus. ${remainingMinutes} minute(s) remaining before automatic time-out.`,
        ...(notificationWarning ? { notificationWarning } : {}),
        outside_since: attendance.outside_since,
        minutes_outside: Math.floor(minutesOutside)
      });
    }

    // -----------------------------------------
    // 30 MINUTES PASSED → AUTOMATIC TIME-OUT
    // -----------------------------------------

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
        title: 'Automatic attendance time-out',
        message: `An automatic time-out was recorded after you were outside ${attendance.campus_name} for 30 minutes.`,
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
      message: 'You have been automatically timed out after being outside campus for 30 minutes.',
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

// Get the authenticated teacher's active-term class schedule.
const getMyClassSchedule = async (req, res) => {
  try {
    if (req.user.role?.toLowerCase() !== 'teacher') {
      return res.status(403).json({
        message: 'This schedule is available to teachers only.'
      });
    }

    const result = await pool.query(
      `
      SELECT
        cs.id,
        cs.course,
        cs.year_level,
        cs.section,
        cs.subject,
        cs.weekday,
        cs.start_time,
        cs.late_after,
        cs.end_time,
        at.school_year,
        at.semester
      FROM class_schedules cs
      JOIN academic_terms at
        ON at.id = cs.academic_term_id
        AND at.is_current = TRUE
      WHERE cs.teacher_user_id = $1
        AND NOT cs.is_archived
      ORDER BY cs.weekday, cs.start_time, cs.course, cs.year_level, cs.section
      `,
      [req.user.userId]
    );

    return res.json({ schedules: result.rows });
  } catch (error) {
    console.error('Get teacher class schedule error:', error);
    return res.status(500).json({
      message: 'Could not load your class schedule.'
    });
  }
};

// The next classes coming up for the signed-in student or teacher: one that is
// happening now, or the next ones today / later this week. Read-only.
const DAY_MS = 24 * 60 * 60 * 1000;

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
      schedule: null,
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

// ---------------------------------------------------------------------------
// Daily schedule
//
// Attendance is per day, not per class. The school day of a student is one
// window: from the start of the first class to the end of the last class on
// that weekday. It is worked out from the class schedules the admin already
// uploads (read only, nothing new is stored).
// ---------------------------------------------------------------------------
const manilaNow = () => {
  const now = new Date();
  return {
    date: new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Manila',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(now),
    time: new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Manila',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23'
    }).format(now)
  };
};

// 0 = Sunday ... 6 = Saturday, the same numbers as class_schedules.weekday.
const weekdayOfDate = (dateText) => new Date(`${dateText}T00:00:00Z`).getUTCDay();

// "08:15:00" -> "8:15 AM"
const clockLabel = (value) => {
  const [hour, minute] = String(value ?? '').split(':').map(Number);
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return '';
  return `${hour % 12 === 0 ? 12 : hour % 12}:${String(minute).padStart(2, '0')} ${hour < 12 ? 'AM' : 'PM'}`;
};

// Minutes since midnight of "HH:MM:SS".
const minutesOfClock = (value) => {
  const [hour, minute] = String(value ?? '').split(':').map(Number);
  return Number.isFinite(hour) && Number.isFinite(minute) ? hour * 60 + minute : null;
};

// The classes that belong to this user: the student's course and year level,
// or the classes a teacher teaches.
//
// College students here have no section, so a class belongs to a student when
// the course and the year level match. The section column is left unused.
const classRoleFilter = (role) =>
  role === 'teacher'
    ? `cs.teacher_user_id = $1`
    : `EXISTS (
         SELECT 1
         FROM students s
         WHERE s.user_id = $1
           AND UPPER(BTRIM(cs.course)) = UPPER(BTRIM(s.course))
           AND UPPER(BTRIM(cs.year_level)) = UPPER(BTRIM(s.year_level))
       )`;

// Map<weekday, { weekday, start_time, end_time, late_after, class_count, campus_name }>
// for the current term. late_after is the late time of the first class of the day.
const loadDailyWindows = async (userId, role) => {
  const result = await pool.query(
    `
    SELECT
      cs.weekday,
      MIN(cs.start_time) AS start_time,
      MAX(cs.end_time) AS end_time,
      (ARRAY_AGG(cs.late_after ORDER BY cs.start_time))[1] AS late_after,
      (ARRAY_AGG(c.campus_name ORDER BY cs.start_time))[1] AS campus_name,
      COUNT(*)::int AS class_count
    FROM class_schedules cs
    JOIN academic_terms at
      ON at.id = cs.academic_term_id AND at.is_current = TRUE
    LEFT JOIN campuses c ON c.id = cs.campus_id
    WHERE NOT cs.is_archived
      AND ${classRoleFilter(role)}
    GROUP BY cs.weekday
    ORDER BY cs.weekday
    `,
    [userId]
  );
  const windows = new Map();
  for (const row of result.rows) {
    windows.set(Number(row.weekday), {
      weekday: Number(row.weekday),
      start_time: row.start_time,
      end_time: row.end_time,
      late_after: row.late_after ?? row.start_time,
      campus_name: row.campus_name ?? null,
      class_count: row.class_count
    });
  }
  return windows;
};

const DAILY_LOOKAHEAD_DAYS = 7;

// GET /api/attendance/daily-schedule
// Today's school day (and the next one when today has none or is over), plus
// the weekly overview.
const getDailySchedule = async (req, res) => {
  try {
    const userId = req.user.userId;
    const role = req.user.role?.toLowerCase();
    if (role !== 'student' && role !== 'teacher') {
      return res.status(403).json({
        message: 'Daily schedules are available to students and teachers only.'
      });
    }

    const windows = await loadDailyWindows(userId, role);
    const { date: today, time: nowTime } = manilaNow();
    const nowMinutes = minutesOfClock(nowTime);
    const todayMs = Date.parse(`${today}T00:00:00Z`);

    const describe = (window, dayOffset) => ({
      weekday: window.weekday,
      day_offset: dayOffset,
      date: new Date(todayMs + dayOffset * DAY_MS).toISOString().slice(0, 10),
      start_time: window.start_time,
      end_time: window.end_time,
      late_after: window.late_after,
      campus_name: window.campus_name,
      class_count: window.class_count
    });

    let todayInfo = null;
    const todayWindow = windows.get(weekdayOfDate(today));
    if (todayWindow) {
      const start = minutesOfClock(todayWindow.start_time);
      const end = minutesOfClock(todayWindow.end_time);
      const state =
        nowMinutes < start ? 'upcoming' : nowMinutes < end ? 'in_session' : 'finished';
      todayInfo = {
        ...describe(todayWindow, 0),
        state,
        minutes_until_start: state === 'upcoming' ? start - nowMinutes : null,
        minutes_until_end: state === 'in_session' ? end - nowMinutes : null
      };
    }

    // Shown when today has no classes or the school day is over.
    let nextDay = null;
    if (!todayInfo || todayInfo.state === 'finished') {
      for (let offset = 1; offset <= DAILY_LOOKAHEAD_DAYS; offset += 1) {
        const window = windows.get(weekdayOfDate(new Date(todayMs + offset * DAY_MS).toISOString().slice(0, 10)));
        if (window) {
          nextDay = describe(window, offset);
          break;
        }
      }
    }

    return res.json({
      has_schedule: windows.size > 0,
      today: todayInfo,
      next_day: nextDay,
      week: [...windows.values()].map((window) => ({
        weekday: window.weekday,
        start_time: window.start_time,
        end_time: window.end_time,
        late_after: window.late_after,
        class_count: window.class_count
      }))
    });
  } catch (error) {
    console.error('Get daily schedule error:', error);
    return res.status(500).json({
      message: 'Could not load your daily schedule.'
    });
  }
};

// Is a student late today? The first time in of the day is late when it is after
// the late time of the first class. No schedule today means not late. Teachers
// and later time ins of the same day are never marked late.
const lateStatusFor = async (userId, role) => {
  if (role !== 'student') return { late: false };
  try {
    const earlier = await pool.query(
      `
      SELECT 1
      FROM attendance
      WHERE user_id = $1
        AND attendance_date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
      LIMIT 1
      `,
      [userId]
    );
    if (earlier.rows.length > 0) return { late: false };

    const windows = await loadDailyWindows(userId, role);
    const { date, time } = manilaNow();
    const window = windows.get(weekdayOfDate(date));
    if (!window) return { late: false };

    const lateAfter = minutesOfClock(window.late_after);
    if (lateAfter !== null && minutesOfClock(time) > lateAfter) {
      return { late: true, lateAfter: window.late_after };
    }
  } catch (error) {
    // A schedule problem must never stop a student from timing in.
    console.error('Late check skipped:', error);
  }
  return { late: false };
};

// Get attendance history for the logged-in student or teacher.
// One record per time in; the status (present, late, timeout) is the daily one.
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
  getMyClassSchedule,
  checkOut,
  updateLocation,
  getActiveAttendance,
  getAttendanceHistory,
  getDailySchedule
};