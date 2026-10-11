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

module.exports = {
  assertEmailConfigured,
  sendPasswordResetCode,
  sendRegistrationDecision
};
