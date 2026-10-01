# geoloc_attendancecapstone

BenildeSafe is a Flutter campus attendance application using the existing API
in `api/`.

## Getting Started

### Flutter frontend

The Flutter project is in `frontend/`. From the project root, run:

```sh
cd frontend
flutter pub get
flutter run
```

Run the API separately from `api/` with `npm run dev`. Configure the API host
for the target device in `frontend/lib/services/api_service.dart`.

## Remaining Modules

### Class schedules and attendance

Administrators first add courses manually from Class Schedules, then open a
course to upload and manage that course's CSV or Excel (`.xlsx`) timetables.
Each upload is scoped to the selected course.
The importer accepts both the normalized template and the source timetable CSV
organized by year, with repeated `CODE,SUBJECT DESCRIPTION,...` headers.
Use one row per class period with these exact headers. The admin schedule
screen can download a matching CSV template:

`course,year_level,section,subject,weekday,start_time,late_after,end_time,teacher_email,campus_code`

Set `campus_code` on every template row to a campus code with a configured
boundary. The original year-by-year timetable CSV does not have a campus
column, so the admin is asked to choose a campus only for that legacy format.
Each class period is assigned to a campus for timetable display and planning.

Student assignments match the course, year, and section in their profile.
Use the same course, year, and section values shown in student profiles. Leave
`section` blank only for schedules that apply to students whose profile has no
section; use an empty cell, not the word `null`.
Template rows match teachers by registered email. In the source timetable format,
instructors without an active account are saved by name; they will not appear as
assigned in the teacher's schedule until their account is linked. Weekday
names (or Sunday=0 through Saturday=6) and
24-hour times such as `08:00`, AM/PM, or noon (`NN`) are accepted. For the
source timetable format, late cutoff defaults to 30 minutes after class start
and can be changed before upload (1–240 minutes),
TBA rows are skipped, and instructor names are matched to active teacher
accounts when possible. Unmatched names remain visible and unassigned until an
account is linked. Schedules repeat weekly throughout their academic term.
Administrators select or create a school-year/semester term manually; creating
a term makes it current, and teacher schedule listings use only schedules in
that current term. Earlier terms remain available for schedule history. Uploads are limited
to the current term, add or update matching rows, and reject invalid or
overlapping schedules without partially importing them. Individual schedules
and all schedules for a course/term can be archived without changing attendance
records.

Attendance time-in is independent of class schedules. Students and teachers can
time in while inside any configured campus boundary, and must time out inside
the same campus boundary. Only one attendance session can be active at a time;
after timing out, a new session can be started. Leaving the boundary starts the
existing 30-minute automatic time-out timer. Class schedule times use Philippine
time; class schedules are informational and do not open or block attendance.
Teachers can open their assigned weekly class schedule from the attendance
screen; it shows active-term schedules only. Administrators can open
teacher attendance reports and filter attendance records by teacher role from
Attendance Records.

Apply [`api/migrations/002_create_class_schedules.sql`](api/migrations/002_create_class_schedules.sql)
after the notification migration to enable this feature, then apply
[`api/migrations/003_allow_unassigned_schedule_instructors.sql`](api/migrations/003_allow_unassigned_schedule_instructors.sql)
to allow schedules to be saved before their teachers have accounts, and
[`api/migrations/004_create_courses.sql`](api/migrations/004_create_courses.sql)
to enable the course catalog, then apply
[`api/migrations/005_add_academic_terms.sql`](api/migrations/005_add_academic_terms.sql)
to add semester-scoped schedules and archival. After applying existing
migrations through 007, apply
[`api/migrations/008_add_schedule_campuses.sql`](api/migrations/008_add_schedule_campuses.sql)
to assign each class schedule to a campus.

### In-app notifications

Attendance check-ins, late check-ins, check-outs, and automatic time-outs are
stored as in-app notifications. Attendance alerts
go to the affected student or teacher, their linked parent (for students),
and administrators.
Notifications are available from each signed-in role's notification icon and
can be individually or collectively marked as read. No external push delivery
is used.

Before starting the API with this feature, apply
[`api/migrations/001_create_notifications.sql`](api/migrations/001_create_notifications.sql)
to the PostgreSQL database. The API uses the existing `notifications.user_id`
recipient column and does not require notification metadata.

### Password reset

The login screen's Forgot Password flow emails a six-digit reset code to
verified active accounts. Registration decision emails (approval or decline)
use the same SMTP configuration. Apply
[`api/migrations/006_create_password_reset_tokens.sql`](api/migrations/006_create_password_reset_tokens.sql)
after the existing migrations. Configure `SMTP_HOST`, `SMTP_PORT`,
`SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS`, and `SMTP_FROM` in `api/.env` using
Gmail's SMTP settings (`smtp.gmail.com`, port `587`, secure `false`) in
`api/.env`. Set `SMTP_USER` and `SMTP_FROM` to your Gmail address and
`SMTP_PASS` to a Google App Password, not your normal password. Google requires
2-Step Verification to create an App Password. Codes expire after 15 minutes,
are limited to five guesses, and can be requested at most once per minute for
an account.
