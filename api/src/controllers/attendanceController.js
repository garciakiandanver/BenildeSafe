const pool = require('../config/database');
const turf = require('@turf/turf');
const { createAttendanceNotifications } = require('../services/notificationService');

// A student who stays outside the campus is warned (together with the parent)
// once they have been outside this many minutes. The automatic time-out is at 30.
const TIMEOUT_WARNING_AFTER_MINUTES = 25;

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

  return { latitude: parsedLatitude, longitude: parsedLongitude };
};

const findCampusAtCoordinates = async (latitude, longitude) => {
  const result = await pool.query(`
    SELECT id, campus_code, campus_name, boundary_coordinates
    FROM campuses
    WHERE boundary_coordinates IS NOT NULL
  `);
  const point = turf.point([longitude, latitude]);
  return result.rows.find((campus) =>
    turf.booleanPointInPolygon(
      point,
      turf.feature(campus.boundary_coordinates)
    )
  ) ?? null;
};

const detectCampus = async (req, res) => {
  try {
    const role = req.user.role?.toLowerCase();
    if (role !== 'student' && role !== 'teacher') {
      return res.status(403).json({
        message: 'Campus detection is available to students and teachers only.'
      });
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

    const campus = await findCampusAtCoordinates(
      coordinates.latitude,
      coordinates.longitude
    );
    if (!campus) {
      return res.status(404).json({
        message: 'Your current location is outside all configured campus boundaries.'
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
    if (role !== 'student' && role !== 'teacher') {
      return res.status(409).json({
        message: 'Attendance is available to students and teachers only.'
      });
    }

    const matchedCampus = await findCampusAtCoordinates(
      latitudeValue,
      longitudeValue
    );
    if (!matchedCampus) {
      return res.status(403).json({
        message: 'You are outside the campus boundary.'
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

    // Campus check-in only records presence. Late or absent for a subject is
    // worked out per class from the class schedule (teacher portal).
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
      RETURNING *
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
        message: `Your attendance was recorded at ${matchedCampus.campus_name}.`,
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
      attendance: attendanceResult.rows[0]
    });
  } catch (error) {
    console.error('CHECK-IN ERROR:', error);
    return res.status(500).json({
      message: 'Server error while checking in.'
    });
  }
};

const getCurrentClassSchedule = async (req, res) => {
  try {
    const userId = req.user.userId;
    const role = req.user.role?.toLowerCase();
    if (role !== 'student' && role !== 'teacher') {
      return res.status(403).json({
        message: 'Class schedules are available to students and teachers only.'
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
        cs.campus_id,
        c.campus_code,
        c.campus_name,
        (
          local_time.current_time >= cs.start_time
          AND local_time.current_time < cs.end_time
        ) AS in_check_in_window,
        EXISTS (
          SELECT 1
          FROM attendance a
          WHERE a.user_id = $1
            AND a.class_schedule_id = cs.id
            AND a.attendance_date =
              (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date
        ) AS already_attended
      FROM class_schedules cs
      JOIN academic_terms at ON at.id = cs.academic_term_id AND at.is_current = TRUE
      LEFT JOIN campuses c ON c.id = cs.campus_id
      CROSS JOIN (
        SELECT
          (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::time AS current_time,
          EXTRACT(DOW FROM (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila'))::int AS current_weekday
      ) local_time
      LEFT JOIN students s ON s.user_id = $1
      WHERE cs.weekday = local_time.current_weekday
        AND NOT cs.is_archived
        AND (
          ($2 = 'student'
            AND UPPER(BTRIM(cs.course)) = UPPER(BTRIM(s.course))
            AND UPPER(BTRIM(cs.year_level)) = UPPER(BTRIM(s.year_level))
            AND COALESCE(UPPER(BTRIM(cs.section)), '') =
              COALESCE(UPPER(BTRIM(s.section)), ''))
          OR ($2 = 'teacher' AND cs.teacher_user_id = $1)
        )
        AND cs.end_time > local_time.current_time
      ORDER BY
        CASE
          WHEN cs.start_time <= local_time.current_time THEN 0
          ELSE 1
        END,
        cs.start_time
      LIMIT 1
      `,
      [userId, role]
    );

    if (result.rows.length === 0) {
      return res.json({ schedule: null });
    }

    const schedule = result.rows[0];
    return res.json({
      schedule: {
        ...schedule,
        can_check_in:
        schedule.in_check_in_window &&
        !schedule.already_attended &&
        Boolean(schedule.campus_id && schedule.campus_name)
      }
    });
  } catch (error) {
    console.error('Get current class schedule error:', error);
    return res.status(500).json({
      message: 'Could not load the current class schedule.'
    });
  }
};

//chechOut or Time-out

const checkOut = async (req, res) => {
  try {
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

    // Create student's current GPS point
    const point = turf.point([coordinates.longitude, coordinates.latitude]);

    // Get the polygon of the campus where the student checked in
    const polygon = turf.feature(
      attendance.boundary_coordinates
    );

    // Check if student is still inside the SAME campus
    const isInsideSameCampus = turf.booleanPointInPolygon(
      point,
      polygon
    );

    if (!isInsideSameCampus) {
      return res.status(403).json({
        message: `You cannot check out here. You checked in at ${attendance.campus_name}. Please check out from the same campus.`
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
      RETURNING *
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
      attendance: updated.rows[0]
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

    // Current GPS point
    const point = turf.point([coordinates.longitude, coordinates.latitude]);

    // Use the SAME campus where the student checked in
    const polygon = turf.feature(
      attendance.boundary_coordinates
    );

    const isInside = turf.booleanPointInPolygon(
      point,
      polygon
    );

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
      RETURNING *
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
      attendance: updated.rows[0]
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

const getActiveAttendance = async (req, res) => {
  try {
    const userId = req.user.userId;

    const result = await pool.query(
      `
      SELECT
        a.id,
        a.campus_id,
        a.attendance_date,
        a.time_in,
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
      time_in: attendance.time_in,
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

// Get attendance history for the logged-in student
const getAttendanceHistory = async (req, res) => {
  try {
    const userId = req.user.userId;

    const result = await pool.query(
      `
      SELECT
        a.id,
        a.attendance_date,
        a.time_in,
        a.time_out,
        a.status,
        c.campus_name
      FROM attendance a
      JOIN campuses c ON c.id = a.campus_id
      WHERE a.user_id = $1
      ORDER BY a.attendance_date DESC, a.time_in DESC
      `,
      [userId]
    );

    return res.json({
      attendance: result.rows
    });

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
  getCurrentClassSchedule,
  getMyClassSchedule,
  checkOut,
  updateLocation,
  getActiveAttendance,
  getAttendanceHistory
};