const pool = require('../config/database');

const getNotifications = async (req, res) => {
  try {
    const [notificationsResult, unreadResult] = await Promise.all([
      pool.query(
        `
        SELECT id, title, message, type, read_at, created_at
        FROM notifications
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT 100
        `,
        [req.user.userId]
      ),
      pool.query(
        `
        SELECT COUNT(*) AS unread_count
        FROM notifications
        WHERE user_id = $1 AND read_at IS NULL
        `,
        [req.user.userId]
      )
    ]);

    return res.json({
      notifications: notificationsResult.rows,
      unreadCount: Number(unreadResult.rows[0].unread_count)
    });
  } catch (error) {
    console.error('Get notifications error:', error);
    return res.status(500).json({
      message: 'Could not load notifications.'
    });
  }
};

const markNotificationRead = async (req, res) => {
  try {
    const result = await pool.query(
      `
      UPDATE notifications
      SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP)
      WHERE id = $1 AND user_id = $2
      RETURNING id, read_at
      `,
      [req.params.id, req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: 'Notification not found.'
      });
    }

    return res.json({
      message: 'Notification marked as read.',
      notification: result.rows[0]
    });
  } catch (error) {
    console.error('Mark notification read error:', error);
    return res.status(500).json({
      message: 'Could not update the notification.'
    });
  }
};

const markAllNotificationsRead = async (req, res) => {
  try {
    await pool.query(
      `
      UPDATE notifications
      SET read_at = CURRENT_TIMESTAMP
      WHERE user_id = $1 AND read_at IS NULL
      `,
      [req.user.userId]
    );

    return res.json({
      message: 'All notifications marked as read.'
    });
  } catch (error) {
    console.error('Mark all notifications read error:', error);
    return res.status(500).json({
      message: 'Could not update notifications.'
    });
  }
};

module.exports = {
  getNotifications,
  markNotificationRead,
  markAllNotificationsRead
};
