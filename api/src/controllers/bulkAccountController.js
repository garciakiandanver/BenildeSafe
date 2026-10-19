const crypto = require('crypto');
const { Readable } = require('stream');
const bcrypt = require('bcrypt');
const ExcelJS = require('exceljs');
const pool = require('../config/database');
const { sendAccountCredentials } = require('../services/emailService');

// ---------------------------------------------------------------------------
// Bulk creation of student and parent accounts from an Excel / CSV file.
//
//   POST /preview   read the file and check every row (nothing is saved)
//   POST /commit    create the accounts of a few checked rows and email them
//   GET  /pending   accounts that still have a temporary password
//   POST /resend    send new temporary passwords to pending accounts
//
// One row = one student and that student's parent. A parent may appear in
// many rows (one per child) and gets a single account. A student belongs to
// exactly one parent.
// ---------------------------------------------------------------------------

const MAX_FILE_ROWS = 1000;
const COMMIT_BATCH_MAX = 10; // rows per /commit call (keeps each call short)
const RESEND_BATCH_MAX = 10;
const EMAIL_CONCURRENCY = 4;

class UserError extends Error {}

// Excel columns. `aliases` are extra header spellings that are accepted
// (headers are compared in lower case with spaces and symbols removed).
const COLUMNS = [
  { key: 'student_number', label: 'Student Number', required: true, aliases: ['studentno', 'studentid'] },
  { key: 'student_first_name', label: 'Student First Name', required: true, aliases: [] },
  { key: 'student_middle_name', label: 'Student Middle Name', required: false, aliases: [] },
  { key: 'student_last_name', label: 'Student Last Name', required: true, aliases: [] },
  { key: 'course', label: 'Course', required: true, aliases: ['coursecode'] },
  { key: 'year_level', label: 'Year Level', required: true, aliases: ['year'] },
  { key: 'section', label: 'Section', required: false, aliases: [] },
  { key: 'student_email', label: 'Student Email', required: true, aliases: [] },
  { key: 'parent_first_name', label: 'Parent First Name', required: true, aliases: [] },
  { key: 'parent_middle_name', label: 'Parent Middle Name', required: false, aliases: [] },
  { key: 'parent_last_name', label: 'Parent Last Name', required: true, aliases: [] },
  { key: 'parent_email', label: 'Parent Email', required: true, aliases: [] },
  {
    key: 'parent_contact_number',
    label: 'Parent Contact Number',
    required: false,
    aliases: ['parentcontact', 'contactnumber', 'parentphone', 'parentmobile']
  }
];

const headerKey = (text) => String(text ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');

const HEADER_LOOKUP = new Map();
for (const column of COLUMNS) {
  HEADER_LOOKUP.set(headerKey(column.label), column.key);
  for (const alias of column.aliases) HEADER_LOOKUP.set(alias, column.key);
}

// ---------------------------------------------------------------------------
// Reading the file
// ---------------------------------------------------------------------------

// Excel cells can hold text, numbers, dates, hyperlinks (emails are often
// turned into links), rich text or formulas. Everything is turned into text.
const cellText = (value) => {
  if (value == null) return '';
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  if (typeof value === 'object') {
    if (Array.isArray(value.richText)) {
      return value.richText.map((part) => part.text ?? '').join('');
    }
    if (value.text != null) return cellText(value.text);
    if (value.result != null) return cellText(value.result);
    return '';
  }
  return String(value);
};

const collapse = (value) => String(value ?? '').replace(/\s+/g, ' ').trim();

const readRowsFromFile = async (buffer, fileName) => {
  const workbook = new ExcelJS.Workbook();
  let sheet;
  try {
    if (/\.csv$/i.test(fileName ?? '')) {
      sheet = await workbook.csv.read(Readable.from(buffer));
    } else {
      await workbook.xlsx.load(buffer);
      sheet = workbook.worksheets[0];
    }
  } catch (error) {
    console.error('Bulk accounts: could not read file:', error);
    throw new UserError(
      'The file could not be read. Use the BenildeSafe template (.xlsx or .csv).'
    );
  }
  if (!sheet || sheet.rowCount === 0) {
    throw new UserError('The file has no data.');
  }

  // The header row is the first of the top rows that has at least 5 known headers.
  let headerRow = null;
  let columnIndex = {};
  for (let r = 1; r <= Math.min(sheet.rowCount, 10); r += 1) {
    const found = {};
    sheet.getRow(r).eachCell({ includeEmpty: false }, (cell, col) => {
      const key = HEADER_LOOKUP.get(headerKey(cellText(cell.value)));
      if (key && !(key in found)) found[key] = col;
    });
    if (Object.keys(found).length >= 5) {
      headerRow = r;
      columnIndex = found;
      break;
    }
  }
  if (headerRow == null) {
    throw new UserError(
      'The column headers were not found. Use the BenildeSafe template and keep its first row.'
    );
  }

  const missing = COLUMNS.filter((c) => c.required && !(c.key in columnIndex)).map(
    (c) => c.label
  );
  if (missing.length > 0) {
    throw new UserError(`These columns are missing: ${missing.join(', ')}.`);
  }

  const rows = [];
  for (let r = headerRow + 1; r <= sheet.rowCount; r += 1) {
    const excelRow = sheet.getRow(r);
    const raw = { row: r };
    let hasValue = false;
    for (const column of COLUMNS) {
      const index = columnIndex[column.key];
      raw[column.key] = index ? collapse(cellText(excelRow.getCell(index).value)) : '';
      if (raw[column.key]) hasValue = true;
    }
    if (!hasValue) continue; // blank row
    rows.push(raw);
    if (rows.length > MAX_FILE_ROWS) {
      throw new UserError(`The file has more than ${MAX_FILE_ROWS} rows. Split it into smaller files.`);
    }
  }
  if (rows.length === 0) {
    throw new UserError('The file has a header row but no students.');
  }
  return rows;
};

// ---------------------------------------------------------------------------
// Checking one row (format only; the database is checked separately)
// ---------------------------------------------------------------------------

const NAME_PATTERN = /^[\p{L}\p{M}][\p{L}\p{M}\s.'-]*$/u;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const STUDENT_NUMBER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9\-_/.]*$/;
const PH_MOBILE_PATTERN = /^(\+?63|0)9\d{9}$/;

const YEAR_WORDS = { first: '1', second: '2', third: '3', fourth: '4', fifth: '5', sixth: '6' };

const normalizeYear = (value) => {
  const text = collapse(value).toLowerCase();
  if (!text) return '';
  const digits = text.match(/\d+/);
  if (digits) return String(parseInt(digits[0], 10));
  for (const [word, number] of Object.entries(YEAR_WORDS)) {
    if (text.includes(word)) return number;
  }
  return text;
};

const normalizePhone = (value) => {
  const text = collapse(value);
  if (!text) return '';
  let digits = text.replace(/[^\d+]/g, '');
  // Excel drops the leading zero of a number such as 09171234567.
  if (/^9\d{9}$/.test(digits)) digits = `0${digits}`;
  return digits;
};

const validateRow = (raw) => {
  const errors = [];
  const warnings = [];
  const data = {
    row: Number.isInteger(Number(raw.row)) ? Number(raw.row) : null,
    student_number: collapse(raw.student_number).toUpperCase(),
    student_first_name: collapse(raw.student_first_name),
    student_middle_name: collapse(raw.student_middle_name),
    student_last_name: collapse(raw.student_last_name),
    course: collapse(raw.course).toUpperCase(),
    year_level: normalizeYear(raw.year_level),
    section: collapse(raw.section).toUpperCase(),
    student_email: collapse(raw.student_email).toLowerCase(),
    parent_first_name: collapse(raw.parent_first_name),
    parent_middle_name: collapse(raw.parent_middle_name),
    parent_last_name: collapse(raw.parent_last_name),
    parent_email: collapse(raw.parent_email).toLowerCase(),
    parent_contact_number: normalizePhone(raw.parent_contact_number)
  };

  const required = [
    ['student_number', 'Student number'],
    ['student_first_name', 'Student first name'],
    ['student_last_name', 'Student last name'],
    ['course', 'Course'],
    ['year_level', 'Year level'],
    ['student_email', 'Student email'],
    ['parent_first_name', 'Parent first name'],
    ['parent_last_name', 'Parent last name'],
    ['parent_email', 'Parent email']
  ];
  for (const [field, label] of required) {
    if (!data[field]) errors.push(`${label} is required.`);
  }

  const names = [
    ['student_first_name', 'Student first name'],
    ['student_middle_name', 'Student middle name'],
    ['student_last_name', 'Student last name'],
    ['parent_first_name', 'Parent first name'],
    ['parent_middle_name', 'Parent middle name'],
    ['parent_last_name', 'Parent last name']
  ];
  for (const [field, label] of names) {
    const value = data[field];
    if (value && (value.length > 60 || !NAME_PATTERN.test(value))) {
      errors.push(`${label} has characters that are not allowed.`);
    }
  }

  if (data.student_number && (data.student_number.length > 40 || !STUDENT_NUMBER_PATTERN.test(data.student_number))) {
    errors.push('Student number can only use letters, numbers and - _ / .');
  }
  if (data.course && data.course.length > 30) errors.push('Course is too long.');
  if (data.year_level && !/^[1-6]$/.test(data.year_level)) {
    errors.push('Year level must be a number from 1 to 6.');
  }
  if (data.section.length > 20) errors.push('Section is too long.');

  for (const [field, label] of [
    ['student_email', 'Student email'],
    ['parent_email', 'Parent email']
  ]) {
    const value = data[field];
    if (value && (value.length > 254 || !EMAIL_PATTERN.test(value))) {
      errors.push(`${label} is not a valid email address.`);
    }
  }
  if (data.student_email && data.student_email === data.parent_email) {
    errors.push('The student and the parent cannot use the same email address.');
  }

  if (!data.parent_contact_number) {
    warnings.push('No parent contact number.');
  } else if (!PH_MOBILE_PATTERN.test(data.parent_contact_number)) {
    warnings.push('The parent contact number does not look like a Philippine mobile number.');
  }

  return { data, errors, warnings };
};

// ---------------------------------------------------------------------------
// Checking against the database (read-only)
// ---------------------------------------------------------------------------

const loadDatabaseFacts = async (rows) => {
  const studentNumbers = [...new Set(rows.map((r) => r.student_number).filter(Boolean))];
  const emails = [
    ...new Set(rows.flatMap((r) => [r.student_email, r.parent_email]).filter(Boolean))
  ];

  const existingStudents = new Set();
  if (studentNumbers.length > 0) {
    const result = await pool.query(
      `
      SELECT UPPER(BTRIM(student_number)) AS student_number
      FROM students
      WHERE UPPER(BTRIM(student_number)) = ANY($1::text[])
      `,
      [studentNumbers]
    );
    for (const row of result.rows) existingStudents.add(row.student_number);
  }

  const accountsByEmail = new Map();
  if (emails.length > 0) {
    const result = await pool.query(
      `
      SELECT LOWER(BTRIM(u.email)) AS email, LOWER(r.name) AS role
      FROM users u
      LEFT JOIN user_roles ur ON ur.user_id = u.id
      LEFT JOIN roles r ON r.id = ur.role_id
      WHERE LOWER(BTRIM(u.email)) = ANY($1::text[])
      `,
      [emails]
    );
    for (const row of result.rows) accountsByEmail.set(row.email, row.role ?? '');
  }

  // The course list is used to catch typos. If it cannot be read, courses are
  // simply not checked.
  let courses = null;
  try {
    const result = await pool.query('SELECT course_code FROM courses');
    const codes = result.rows
      .map((row) => collapse(row.course_code).toUpperCase())
      .filter(Boolean);
    if (codes.length > 0) courses = new Set(codes);
  } catch (error) {
    console.error('Bulk accounts: course list not available:', error.message);
  }

  return { existingStudents, accountsByEmail, courses };
};

// Returns { errors, parentExists } for one row that already passed validateRow.
const checkRowAgainstDatabase = (data, facts) => {
  const errors = [];
  if (facts.existingStudents.has(data.student_number)) {
    errors.push('This student number already exists.');
  }
  if (facts.accountsByEmail.has(data.student_email)) {
    errors.push('The student email is already registered.');
  }
  let parentExists = false;
  if (facts.accountsByEmail.has(data.parent_email)) {
    if (facts.accountsByEmail.get(data.parent_email) === 'parent') {
      parentExists = true;
    } else {
      errors.push('The parent email is already used by a student, teacher or admin account.');
    }
  }
  if (facts.courses && data.course && !facts.courses.has(data.course)) {
    errors.push(`Course "${data.course}" is not in the course list.`);
  }
  return { errors, parentExists };
};

// Checks that only make sense across the whole file.
const checkWholeFile = (items) => {
  const byStudentNumber = new Map();
  const byStudentEmail = new Map();
  const parentEmails = new Set();
  const studentEmails = new Set();
  const firstParentRow = new Map();

  const add = (map, key, row) => {
    if (!key) return;
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(row);
  };

  for (const item of items) {
    const { data } = item;
    add(byStudentNumber, data.student_number, data.row);
    add(byStudentEmail, data.student_email, data.row);
    if (data.parent_email) parentEmails.add(data.parent_email);
    if (data.student_email) studentEmails.add(data.student_email);
  }

  for (const item of items) {
    const { data } = item;
    const sameNumber = byStudentNumber.get(data.student_number) ?? [];
    if (sameNumber.length > 1) {
      item.errors.push(
        `This student number appears more than once in the file (rows ${sameNumber.join(', ')}). A student can only have one parent.`
      );
    }
    const sameEmail = byStudentEmail.get(data.student_email) ?? [];
    if (sameEmail.length > 1) {
      item.errors.push(
        `This student email appears more than once in the file (rows ${sameEmail.join(', ')}).`
      );
    }
    if (data.student_email && parentEmails.has(data.student_email)) {
      item.errors.push('The student email is also used as a parent email in this file.');
    }
    if (data.parent_email && studentEmails.has(data.parent_email)) {
      item.errors.push('The parent email is also used as a student email in this file.');
    }

    // The same parent email on several rows must describe the same parent.
    const first = firstParentRow.get(data.parent_email);
    if (!first) {
      if (data.parent_email) firstParentRow.set(data.parent_email, data);
    } else {
      const sameName = (a, b) => a.toLowerCase() === b.toLowerCase();
      if (
        !sameName(first.parent_first_name, data.parent_first_name) ||
        !sameName(first.parent_last_name, data.parent_last_name)
      ) {
        item.warnings.push(
          `The parent name differs from row ${first.row}, which uses the same email. The details from the first row are kept.`
        );
      }
    }
  }
};

// ---------------------------------------------------------------------------
// Passwords and emails
// ---------------------------------------------------------------------------

const UPPER = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const LOWER = 'abcdefghijkmnopqrstuvwxyz';
const DIGITS = '23456789';

// 10 characters with at least one capital letter, one small letter and one
// number. Look-alike characters (0/O, 1/l/I) are left out so it is easy to type.
const generateTempPassword = () => {
  const pick = (set) => set[crypto.randomInt(set.length)];
  const all = UPPER + LOWER + DIGITS;
  const chars = [pick(UPPER), pick(LOWER), pick(DIGITS)];
  while (chars.length < 10) chars.push(pick(all));
  for (let i = chars.length - 1; i > 0; i -= 1) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
};

const describeEmailError = (error) => {
  const text = String(error?.response ?? error?.message ?? '');
  if (text.startsWith('Email delivery is not configured')) {
    return 'Email delivery is not configured.';
  }
  if (error?.code === 'EAUTH') {
    return 'The email server rejected the sign-in. Check the SMTP settings.';
  }
  if (/quota|limit exceeded|too many/i.test(text)) {
    return 'The daily email limit was reached. Try again later.';
  }
  if (error?.code === 'EENVELOPE' || /recipient|invalid.*address/i.test(text)) {
    return 'The email address was rejected.';
  }
  return 'The email could not be sent.';
};

const runWithLimit = async (items, limit, worker) => {
  let next = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next;
      next += 1;
      await worker(items[index], index);
    }
  });
  await Promise.all(runners);
};

const joinName = (...parts) => parts.filter(Boolean).join(' ');

// ---------------------------------------------------------------------------
// Creating the accounts of one row
// ---------------------------------------------------------------------------

const loadRoleIds = async () => {
  const result = await pool.query(
    `SELECT id, LOWER(name) AS name FROM roles WHERE LOWER(name) IN ('student', 'parent')`
  );
  const ids = Object.fromEntries(result.rows.map((row) => [row.name, row.id]));
  if (ids.student == null || ids.parent == null) {
    throw new Error('The student and parent roles were not found in the roles table.');
  }
  return ids;
};

const insertAccount = async (client, { email, passwordHash, roleId }) => {
  const user = await client.query(
    `
    INSERT INTO users (id, email, password_hash, status, email_verified, must_change_password)
    VALUES (gen_random_uuid(), $1, $2, 'active', TRUE, TRUE)
    RETURNING id
    `,
    [email, passwordHash]
  );
  const userId = user.rows[0].id;
  await client.query(`INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2)`, [
    userId,
    roleId
  ]);
  return userId;
};

// Creates the student (and the parent, unless that parent already has an
// account) in one transaction. Returns the temporary passwords to email.
const createAccounts = async (data, roleIds) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    let parentId;
    let parentCredentials = null;
    const existingParent = await client.query(
      `
      SELECT p.id
      FROM users u
      JOIN parents p ON p.user_id = u.id
      WHERE LOWER(BTRIM(u.email)) = $1
      `,
      [data.parent_email]
    );
    if (existingParent.rowCount > 0) {
      parentId = existingParent.rows[0].id;
    } else {
      const password = generateTempPassword();
      const parentUserId = await insertAccount(client, {
        email: data.parent_email,
        passwordHash: await bcrypt.hash(password, 10),
        roleId: roleIds.parent
      });
      const parent = await client.query(
        `
        INSERT INTO parents (id, user_id, first_name, middle_name, last_name, contact_number)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, $5)
        RETURNING id
        `,
        [
          parentUserId,
          data.parent_first_name,
          data.parent_middle_name || null,
          data.parent_last_name,
          data.parent_contact_number || null
        ]
      );
      parentId = parent.rows[0].id;
      parentCredentials = {
        email: data.parent_email,
        fullName: joinName(
          data.parent_first_name,
          data.parent_middle_name,
          data.parent_last_name
        ),
        role: 'parent',
        tempPassword: password
      };
    }

    const studentPassword = generateTempPassword();
    const studentUserId = await insertAccount(client, {
      email: data.student_email,
      passwordHash: await bcrypt.hash(studentPassword, 10),
      roleId: roleIds.student
    });
    await client.query(
      `
      INSERT INTO students (
        id, user_id, student_number, first_name, middle_name, last_name,
        course, year_level, section, parent_id
      )
      VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9)
      `,
      [
        studentUserId,
        data.student_number,
        data.student_first_name,
        data.student_middle_name || null,
        data.student_last_name,
        data.course,
        data.year_level,
        data.section || null,
        parentId
      ]
    );

    await client.query('COMMIT');
    return {
      student: {
        email: data.student_email,
        fullName: joinName(
          data.student_first_name,
          data.student_middle_name,
          data.student_last_name
        ),
        role: 'student',
        tempPassword: studentPassword
      },
      parent: parentCredentials
    };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
};

const describeDatabaseError = (error) => {
  if (error?.code === '23505') {
    if (error.constraint === 'students_student_number_key') {
      return 'This student number already exists.';
    }
    if (error.constraint === 'users_email_key') {
      return 'An account with this email already exists.';
    }
    return 'Duplicate data was found.';
  }
  return 'The accounts could not be created.';
};

// ---------------------------------------------------------------------------
// Request handlers
// ---------------------------------------------------------------------------

const sendError = (res, error, fallback) => {
  if (error instanceof UserError) {
    return res.status(400).json({ message: error.message });
  }
  console.error(fallback, error);
  return res.status(500).json({ message: fallback });
};

// POST /api/admin/bulk-accounts/preview   (multipart, field "file")
const previewBulkAccounts = async (req, res) => {
  try {
    if (!req.file || !req.file.buffer || req.file.buffer.length === 0) {
      throw new UserError('Choose an Excel (.xlsx) or CSV file first.');
    }

    const rawRows = await readRowsFromFile(req.file.buffer, req.file.originalname);
    const items = rawRows.map((raw) => ({ ...validateRow(raw), parentExists: false }));

    const facts = await loadDatabaseFacts(items.map((item) => item.data));
    for (const item of items) {
      if (item.errors.length > 0) continue;
      const check = checkRowAgainstDatabase(item.data, facts);
      item.errors.push(...check.errors);
      item.parentExists = check.parentExists;
    }
    checkWholeFile(items);

    const ready = items.filter((item) => item.errors.length === 0);
    const newParents = new Set();
    const existingParents = new Set();
    for (const item of ready) {
      (item.parentExists ? existingParents : newParents).add(item.data.parent_email);
    }
    // A parent whose account already exists is not counted as new.
    for (const email of existingParents) newParents.delete(email);

    return res.json({
      summary: {
        total_rows: items.length,
        ready_rows: ready.length,
        error_rows: items.length - ready.length,
        warning_rows: items.filter((item) => item.warnings.length > 0).length,
        students_to_create: ready.length,
        parents_to_create: newParents.size,
        existing_parents: existingParents.size,
        emails_to_send: ready.length + newParents.size,
        courses_checked: facts.courses != null
      },
      rows: items.map((item) => ({
        row: item.data.row,
        status: item.errors.length === 0 ? 'ok' : 'error',
        errors: item.errors,
        warnings: item.warnings,
        parent_exists: item.parentExists,
        data: item.data
      }))
    });
  } catch (error) {
    return sendError(res, error, 'Could not check the file.');
  }
};

// POST /api/admin/bulk-accounts/commit   Body: { rows: [ <data of checked rows> ] }
const commitBulkAccounts = async (req, res) => {
  try {
    const rows = req.body?.rows;
    if (!Array.isArray(rows) || rows.length === 0) {
      throw new UserError('There are no rows to import.');
    }
    if (rows.length > COMMIT_BATCH_MAX) {
      throw new UserError(`Send at most ${COMMIT_BATCH_MAX} rows at a time.`);
    }

    // Rows are checked again here: the client is never trusted.
    const items = rows.map((raw) => validateRow(raw && typeof raw === 'object' ? raw : {}));
    const facts = await loadDatabaseFacts(
      items.filter((item) => item.errors.length === 0).map((item) => item.data)
    );
    const roleIds = await loadRoleIds();

    const results = [];
    const emailJobs = [];

    // Step 1: create the accounts, one row at a time.
    for (const item of items) {
      const { data } = item;
      const result = {
        row: data.row,
        student_number: data.student_number,
        student_name: joinName(data.student_first_name, data.student_last_name),
        status: 'error',
        message: '',
        parent_created: false,
        student_email_sent: false,
        parent_email_sent: null,
        email_message: ''
      };
      results.push(result);

      const problems = [...item.errors];
      if (problems.length === 0) {
        problems.push(...checkRowAgainstDatabase(data, facts).errors);
      }
      if (problems.length > 0) {
        result.message = problems.join(' ');
        continue;
      }

      try {
        const created = await createAccounts(data, roleIds);
        result.status = 'created';
        result.parent_created = created.parent != null;
        emailJobs.push({ result, kind: 'student', credentials: created.student });
        if (created.parent) {
          emailJobs.push({ result, kind: 'parent', credentials: created.parent });
        }
      } catch (error) {
        console.error('Bulk accounts: create failed for row', data.row, error);
        result.message = describeDatabaseError(error);
      }
    }

    // Step 2: email everyone their temporary password.
    await runWithLimit(emailJobs, EMAIL_CONCURRENCY, async (job) => {
      let sent = false;
      let reason = '';
      try {
        await sendAccountCredentials(job.credentials);
        sent = true;
      } catch (error) {
        console.error('Bulk accounts: email failed:', error);
        reason = describeEmailError(error);
      }
      const label = job.kind === 'parent' ? 'Parent' : 'Student';
      if (job.kind === 'student') job.result.student_email_sent = sent;
      else job.result.parent_email_sent = sent;
      if (!sent) {
        job.result.email_message = [job.result.email_message, `${label}: ${reason}`]
          .filter(Boolean)
          .join(' ');
      }
    });

    return res.json({
      results,
      summary: {
        created: results.filter((r) => r.status === 'created').length,
        errors: results.filter((r) => r.status === 'error').length,
        emails_failed: emailJobs.filter((job) =>
          job.kind === 'student'
            ? !job.result.student_email_sent
            : job.result.parent_email_sent === false
        ).length
      }
    });
  } catch (error) {
    return sendError(res, error, 'Could not create the accounts.');
  }
};

const fullNameSql = (alias) => `
  NULLIF(BTRIM(CONCAT_WS(' ',
    NULLIF(BTRIM(${alias}.first_name), ''),
    NULLIF(BTRIM(${alias}.middle_name), ''),
    NULLIF(BTRIM(${alias}.last_name), ''))), '')`;

const ACCOUNT_SELECT = `
  SELECT
    u.id,
    u.email,
    LOWER(r.name) AS role,
    s.student_number,
    COALESCE(${fullNameSql('s')}, ${fullNameSql('t')}, ${fullNameSql('p')}) AS full_name
  FROM users u
  LEFT JOIN user_roles ur ON ur.user_id = u.id
  LEFT JOIN roles r ON r.id = ur.role_id
  LEFT JOIN students s ON s.user_id = u.id
  LEFT JOIN teachers t ON t.user_id = u.id
  LEFT JOIN parents p ON p.user_id = u.id`;

// GET /api/admin/bulk-accounts/pending
// Accounts that still have a temporary password (they have not signed in yet).
const getPendingAccounts = async (req, res) => {
  try {
    const result = await pool.query(
      `
      ${ACCOUNT_SELECT}
      WHERE u.must_change_password = TRUE
        AND u.status = 'active'
      ORDER BY LOWER(r.name), full_name, u.email
      LIMIT 2000
      `
    );
    return res.json({ accounts: result.rows });
  } catch (error) {
    return sendError(res, error, 'Could not load the accounts.');
  }
};

// POST /api/admin/bulk-accounts/resend   Body: { emails: [ ... ] }
// Gives each listed account a NEW temporary password and emails it. Only
// accounts that have never changed their temporary password are touched.
const resendCredentials = async (req, res) => {
  try {
    const emails = [
      ...new Set(
        (Array.isArray(req.body?.emails) ? req.body.emails : [])
          .map((email) => collapse(email).toLowerCase())
          .filter(Boolean)
      )
    ];
    if (emails.length === 0) throw new UserError('Choose at least one account.');
    if (emails.length > RESEND_BATCH_MAX) {
      throw new UserError(`Send at most ${RESEND_BATCH_MAX} accounts at a time.`);
    }

    const results = [];
    const jobs = [];
    for (const email of emails) {
      const result = { email, sent: false, message: '' };
      results.push(result);

      const found = await pool.query(
        `
        ${ACCOUNT_SELECT}
        WHERE LOWER(BTRIM(u.email)) = $1
          AND u.must_change_password = TRUE
          AND u.status = 'active'
        LIMIT 1
        `,
        [email]
      );
      if (found.rowCount === 0) {
        result.message = 'This account has already signed in, or it does not exist.';
        continue;
      }

      const account = found.rows[0];
      const password = generateTempPassword();
      const updated = await pool.query(
        `
        UPDATE users
        SET password_hash = $1, must_change_password = TRUE, updated_at = CURRENT_TIMESTAMP
        WHERE id = $2 AND must_change_password = TRUE
        `,
        [await bcrypt.hash(password, 10), account.id]
      );
      if (updated.rowCount === 0) {
        result.message = 'This account has already signed in.';
        continue;
      }
      jobs.push({
        result,
        credentials: {
          email: account.email,
          fullName: account.full_name,
          role: account.role,
          tempPassword: password
        }
      });
    }

    await runWithLimit(jobs, EMAIL_CONCURRENCY, async (job) => {
      try {
        await sendAccountCredentials(job.credentials);
        job.result.sent = true;
      } catch (error) {
        console.error('Bulk accounts: resend failed:', error);
        job.result.message = describeEmailError(error);
      }
    });

    return res.json({
      results,
      summary: {
        sent: results.filter((r) => r.sent).length,
        failed: results.filter((r) => !r.sent).length
      }
    });
  } catch (error) {
    return sendError(res, error, 'Could not resend the emails.');
  }
};

module.exports = {
  COLUMNS,
  previewBulkAccounts,
  commitBulkAccounts,
  getPendingAccounts,
  resendCredentials
};
