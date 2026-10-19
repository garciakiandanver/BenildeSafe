const nodemailer = require('nodemailer');

let transporter;

const getTransporter = () => {
  const host = process.env.SMTP_HOST;
  const port = Number(process.env.SMTP_PORT);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  const from = process.env.SMTP_FROM;

  if (!host || !Number.isInteger(port) || !user || !pass || !from) {
    throw new Error('Email delivery is not configured. Set the SMTP environment variables.');
  }

  if (!transporter) {
    transporter = nodemailer.createTransport({
      host,
      port,
      secure: process.env.SMTP_SECURE === 'true',
      auth: { user, pass }
    });
  }

  return { transporter, from };
};

const assertEmailConfigured = () => {
  getTransporter();
};

const sendPasswordResetCode = async (email, code) => {
  const { transporter: mailer, from } = getTransporter();
  await mailer.sendMail({
    from,
    to: email,
    subject: 'Your password reset code',
    text: [
      `Your password reset code is ${code}.`,
      '',
      'Enter this code in the Forgot Password screen to set a new password.',
      'This code expires in 15 minutes. If you did not request a reset, ignore this email.'
    ].join('\n')
  });
};

const sendRegistrationDecision = async ({
  email,
  fullName,
  role,
  approved
}) => {
  const { transporter: mailer, from } = getTransporter();
  const decision = approved ? 'approved' : 'declined';
  const roleText = role ? ` for the ${role} role` : '';
  const accountDetails = approved
    ? 'Your account has been created and is ready to use. You can now sign in with the email address and password you provided during registration.'
    : 'Your registration request was not approved at this time. If you believe this was a mistake, please contact the school administrator.';

  await mailer.sendMail({
    from,
    to: email,
    subject: `Registration request ${decision}`,
    text: [
      `Hello ${fullName},`,
      '',
      `Your registration request${roleText} has been ${decision}.`,
      '',
      accountDetails,
      '',
      'This is an automated message. Please do not reply.'
    ].join('\n')
  });
};

const escapeHtml = (value) =>
  String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[char]));

// Sends the login details of a new account that has a temporary password.
// The web link and the APK link are shown at the bottom of the email.
//   APP_WEB_URL        (optional) defaults to https://benildesafe.vercel.app
//   APK_DOWNLOAD_URL   (optional) the APK line is left out when it is not set
const sendAccountCredentials = async ({
  email,
  fullName,
  role,
  tempPassword
}) => {
  const { transporter: mailer, from } = getTransporter();
  const webUrl = (process.env.APP_WEB_URL || 'https://benildesafe.vercel.app').trim();
  const apkUrl = (process.env.APK_DOWNLOAD_URL || '').trim();

  const roleName = String(role ?? '').toLowerCase();
  const roleText = ['parent', 'student', 'teacher'].includes(roleName)
    ? roleName
    : 'user';
  const purpose = roleName === 'parent'
    ? "Use it to follow your child's campus attendance and safety notifications."
    : roleName === 'student'
      ? 'Use it to record your campus attendance.'
      : 'Use it to sign in to the system.';
  const name = fullName || 'there';

  const text = [
    `Hello ${name},`,
    '',
    `A BenildeSafe account has been created for you as a ${roleText}. ${purpose}`,
    '',
    'Your sign-in details',
    `Email: ${email}`,
    `Temporary password: ${tempPassword}`,
    '',
    'You will be asked to create your own password the first time you sign in.',
    'Please do not share this password with anyone.',
    '',
    '----------------------------------------',
    'Open BenildeSafe',
    `Web app: ${webUrl}`,
    ...(apkUrl ? [`Android app (APK): ${apkUrl}`] : []),
    '',
    'This is an automated message. Please do not reply.'
  ].join('\n');

  const html = `
<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.5;color:#1f2937;max-width:560px">
  <p>Hello ${escapeHtml(name)},</p>
  <p>A BenildeSafe account has been created for you as a ${escapeHtml(roleText)}. ${escapeHtml(purpose)}</p>
  <p style="margin:18px 0 6px"><strong>Your sign-in details</strong></p>
  <table style="border-collapse:collapse;background:#f3f4f6;border-radius:8px" cellpadding="10">
    <tr><td style="color:#6b7280">Email</td><td><strong>${escapeHtml(email)}</strong></td></tr>
    <tr><td style="color:#6b7280">Temporary password</td><td><strong style="font-family:Consolas,Menlo,monospace;font-size:17px;letter-spacing:1px">${escapeHtml(tempPassword)}</strong></td></tr>
  </table>
  <p>You will be asked to create your own password the first time you sign in. Please do not share this password with anyone.</p>
  <hr style="border:none;border-top:1px solid #e5e7eb;margin:22px 0">
  <p style="margin:0 0 8px"><strong>Open BenildeSafe</strong></p>
  <p style="margin:0 0 6px">Web app: <a href="${escapeHtml(webUrl)}">${escapeHtml(webUrl)}</a></p>
  ${apkUrl ? `<p style="margin:0 0 6px">Android app (APK): <a href="${escapeHtml(apkUrl)}">${escapeHtml(apkUrl)}</a></p>` : ''}
  <p style="color:#6b7280;font-size:13px;margin-top:22px">This is an automated message. Please do not reply.</p>
</div>`.trim();

  await mailer.sendMail({
    from,
    to: email,
    subject: 'Your BenildeSafe account',
    text,
    html
  });
};

module.exports = {
  assertEmailConfigured,
  sendPasswordResetCode,
  sendRegistrationDecision,
  sendAccountCredentials
};
