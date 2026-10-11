const pool = require('../config/database');

// The notifications table only allows the categories 'Attendance', 'Reminder'
// and 'System' in its `type` column (notifications_type_check). Every attendance
// notification is saved as 'Attendance'; the specific event
// (attendance_check_in / attendance_check_out / attendance_timeout) is kept in
// metadata.event.
const NOTIFICATION_CATEGORY = 'Attendance';

// Events that can be triggered repeatedly by frequent location updates. For each,
// do not send the same notification again within this many minutes.
const DUPLICATE_WINDOW_MINUTES = {
  attendance_left_boundary: 10,
  attendance_timeout_warning: 10
};

// Builds the parent-facing title/message for each attendance event.
// `childName` is the student's full name, `campusName` the campus involved.
const buildParentText = (type, childName, campusName, status) => {
  const place = campusName || 'campus';

  switch (type) {
    case 'attendance_check_in':
      return {
        title: `${childName} checked in`,
        message:
          status === 'late'
            ? `${childName} checked in late at ${place}.`
            : `${childName} checked in at ${place}.`
      };
    case 'attendance_check_out':
      return {
        title: `${childName} checked out`,
        message: `${childName} checked out of ${place}.`
      };
    case 'attendance_left_boundary':
      return {
        title: `${childName} left the campus`,
        message: `${childName} left the boundary of ${place}. They will be timed out automatically in 30 minutes unless they return.`
      };
    case 'attendance_returned':
      return {
        title: `${childName} is back on campus`,
        message: `${childName} is back inside ${place}. The automatic time-out timer has been cancelled.`
      };
    case 'attendance_timeout_warning':
      return {
        title: `${childName} will be timed out soon`,
        message: `${childName} has been outside ${place} for almost 30 minutes and will be timed out automatically in a few minutes unless they return.`
      };
    case 'attendance_timeout':
      return {
        title: `${childName} was timed out`,
        message: `${childName} was automatically timed out from ${place} after being outside campus for 30 minutes.`
      };
    default:
      return null;
  }
};

/**
 * Creates the notifications for one attendance event.
 *
 * - The user who triggered the event always gets the title/message passed in
 *   (written in "you/your" wording by the caller).
 * - If that user is a student linked to a parent, the parent also gets a
 *   message that names the child.
 * - Teachers have no parent, so only they receive a notification.
 *
 * Throws on database errors. Callers wrap this in try/catch so a notification
 * problem never blocks the attendance action itself.
 */
const createAttendanceNotifications = async ({
  userId,
  title,
  message,
  type: event // 'attendance_check_in' | 'attendance_check_out' | 'attendance_left_boundary' | 'attendance_returned' | 'attendance_timeout_warning' | 'attendance_timeout'
}) => {
  // 1. Is this user a student, and who is the linked parent?
  const studentResult = await pool.query(
    `
    SELECT
      s.id AS student_id,
      s.first_name,
      s.middle_name,
      s.last_name,
      p.user_id AS parent_user_id
    FROM students s
    LEFT JOIN parents p ON p.id = s.parent_id
    WHERE s.user_id = $1
    LIMIT 1
    `,
    [userId]
  );
  const student = studentResult.rows[0] ?? null;

  // 2. Most recent attendance record: gives us the campus name and status.
  const attendanceResult = await pool.query(
    `
    SELECT a.id, a.status, c.campus_name
    FROM attendance a
    LEFT JOIN campuses c ON c.id = a.campus_id
    WHERE a.user_id = $1
    ORDER BY a.time_in DESC NULLS LAST
    LIMIT 1
    `,
    [userId]
  );
  const attendance = attendanceResult.rows[0] ?? null;

  // Location updates arrive often (and GPS can flicker at the boundary edge),
  // so repeatable events are sent at most once per window per attendance session.
  const windowMinutes = DUPLICATE_WINDOW_MINUTES[event];
  if (windowMinutes && attendance) {
    const recent = await pool.query(
      `
      SELECT 1
      FROM notifications
      WHERE user_id = $1
        AND metadata->>'event' = $2
        AND metadata->>'attendance_id' = $3::text
        AND created_at > CURRENT_TIMESTAMP - ($4::int * INTERVAL '1 minute')
      LIMIT 1
      `,
      [userId, event, String(attendance.id), windowMinutes]
    );
    if (recent.rowCount > 0) return;
  }

  // A "back on campus" notification only makes sense after a "left the campus"
  // one was actually sent. Pair them: send it only if the latest "left" is newer
  // than the latest "back" for this attendance session.
  if (event === 'attendance_returned') {
    if (!attendance) return;
    const pair = await pool.query(
      `
      SELECT
        MAX(created_at) FILTER (
          WHERE metadata->>'event' = 'attendance_left_boundary'
        ) AS last_left,
        MAX(created_at) FILTER (
          WHERE metadata->>'event' = 'attendance_returned'
        ) AS last_returned
      FROM notifications
      WHERE user_id = $1
        AND metadata->>'attendance_id' = $2::text
      `,
      [userId, String(attendance.id)]
    );
    const { last_left: lastLeft, last_returned: lastReturned } = pair.rows[0];
    if (!lastLeft || (lastReturned && lastLeft <= lastReturned)) return;
  }

  // 3. Build the list of recipients (the user themself, then the parent).
  const recipientIds = [userId];
  const titles = [title];
  const messages = [message];

  if (student && student.parent_user_id) {
    // Full name as "First Middle Last"
    const childName = [student.first_name, student.middle_name, student.last_name]
      .map((part) => String(part ?? '').trim())
      .filter(Boolean)
      .join(' ');
    const parentText = buildParentText(
      event,
      childName,
      attendance?.campus_name,
      attendance?.status
    );

    if (parentText) {
      recipientIds.push(student.parent_user_id);
      titles.push(parentText.title);
      messages.push(parentText.message);
    }
  }

  const metadata = {
    event,
    student_user_id: userId,
    student_id: student?.student_id ?? null,
    attendance_id: attendance?.id ?? null
  };

  // 4. Insert every notification in a single statement.
  await pool.query(
    `
    INSERT INTO notifications (user_id, title, message, type, metadata)
    SELECT t.user_id, t.title, t.message, $4::varchar, $5::jsonb
    FROM unnest($1::uuid[], $2::text[], $3::text[])
      AS t(user_id, title, message)
    `,
    [recipientIds, titles, messages, NOTIFICATION_CATEGORY, JSON.stringify(metadata)]
  );
};

module.exports = {
  createAttendanceNotifications
};